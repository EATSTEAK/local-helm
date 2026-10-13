require "minitest/autorun"
require "yaml"
require "json"
require "open3"
require "tmpdir"
require "base64"
require "digest"

ROOT = File.expand_path("..", __dir__)
Dir.chdir(ROOT)

class PhoenixConfigurationTest < Minitest::Test
  def self.command(*args)
    output, error, status = Open3.capture3(*args)
    raise "#{args.first} failed: #{error}" unless status.success?
    output
  end

  def self.docs(text)
    YAML.load_stream(text).compact
  end

  def self.postgres
    @postgres ||= docs(command("helm", "template", "shared-postgres", "charts/shared-postgres",
      "-n", "default", "-f", "apps/colima/shared-postgres/values.yaml"))
  end

  def self.phoenix
    @phoenix ||= begin
      chart = ENV.fetch("PHOENIX_CHART_PATH")
      rendered = command("helm", "template", "phoenix", chart, "-n", "default",
        "-f", "apps/colima/phoenix/values.yaml")
      release = YAML.load_file("apps/colima/phoenix/helmrelease.yaml")
      patches = release.dig("spec", "postRenderers", 0, "kustomize", "patches")
      # Run the actual Flux post-renderer patches, not a hand-written substitute.
      Dir.mktmpdir("phoenix-render-") do |dir|
        File.write(File.join(dir, "rendered.yaml"), rendered)
        File.write(File.join(dir, "kustomization.yaml"), {
          "apiVersion" => "kustomize.config.k8s.io/v1beta1", "kind" => "Kustomization",
          "resources" => ["rendered.yaml"], "patches" => patches
        }.to_yaml)
        docs(command("kubectl", "kustomize", dir))
      end
    end
  end

  def resource(docs, kind, name)
    docs.find { |d| d["kind"] == kind && d.dig("metadata", "name") == name } ||
      flunk("Missing #{kind}/#{name}")
  end

  def test_postgres_is_single_small_persistent_instance
    set = resource(self.class.postgres, "StatefulSet", "shared-postgres")
    assert_equal 1, set.dig("spec", "replicas")
    pod = set.dig("spec", "template", "spec")
    refute pod["automountServiceAccountToken"]
    assert_equal 999, pod.dig("securityContext", "runAsUser")
    container = pod.fetch("containers").first
    assert_equal "256Mi", container.dig("resources", "requests", "memory")
    assert_equal "1Gi", container.dig("resources", "limits", "memory")
    assert_match(/@sha256:[a-f0-9]{64}\z/, container.fetch("image"))
    assert container.dig("securityContext", "readOnlyRootFilesystem")
    pvc = resource(self.class.postgres, "PersistentVolumeClaim", "shared-postgres-data")
    assert_equal "8Gi", pvc.dig("spec", "resources", "requests", "storage")
    assert_equal "keep", pvc.dig("metadata", "annotations", "helm.sh/resource-policy")
  end

  def test_database_bootstrap_is_a_waited_hook_using_existing_secrets
    job = resource(self.class.postgres, "Job", "shared-postgres-bootstrap-phoenix")
    assert_equal "post-install,post-upgrade", job.dig("metadata", "annotations", "helm.sh/hook")
    assert_equal 300, job.dig("spec", "activeDeadlineSeconds")
    pod = job.dig("spec", "template")
    assert_equal "true", pod.dig("metadata", "labels", "shared-postgres-client")
    env = pod.dig("spec", "containers", 0, "env").to_h { |e| [e["name"], e] }
    assert_equal "shared-postgres-auth", env.dig("PGPASSWORD", "valueFrom", "secretKeyRef", "name")
    assert_equal "phoenix-secret", env.dig("APP_PASSWORD", "valueFrom", "secretKeyRef", "name")
    assert_equal "phoenix", env.dig("APP_DATABASE", "value")
    assert_equal "20", env.dig("APP_CONNECTION_LIMIT", "value")
    refute self.class.postgres.any? { |d| d["kind"] == "Secret" }
  end

  def test_database_bootstrap_waits_for_connectivity_without_retrying_sql_errors
    job = resource(self.class.postgres, "Job", "shared-postgres-bootstrap-phoenix")
    assert_equal 300, job.dig("spec", "activeDeadlineSeconds"), "Must bound the readiness wait"
    container = job.dig("spec", "template", "spec", "containers", 0)
    [1, 3].product([0, 2, 3]).each do |ready_after, sql_status|
      Dir.mktmpdir("postgres-readiness-test-") do |dir|
        # Exercise the rendered hook command without network access or credentials.
        %w[pg_isready sleep psql].each do |name|
          path = File.join(dir, name)
          File.write(path, <<~'SH')
            #!/bin/sh
            name=$(basename "$0")
            echo "$name" >> "$CALL_LOG"
            case "$name" in
              pg_isready) [ "$(grep -c '^pg_isready$' "$CALL_LOG")" -ge "$READY_AFTER" ] ;;
              sleep) exit 0 ;;
              psql)
                printf '%s\n' "$@" > "$PSQL_ARGS"
                exit "$PSQL_STATUS"
                ;;
            esac
          SH
          File.chmod(0o755, path)
        end
        env = {"PATH" => "#{dir}:#{ENV.fetch("PATH")}", "CALL_LOG" => File.join(dir, "calls"),
               "PSQL_ARGS" => File.join(dir, "psql-args"), "READY_AFTER" => ready_after.to_s,
               "PSQL_STATUS" => sql_status.to_s}
        _, error, status = Open3.capture3(env, *container.fetch("command"), *container.fetch("args", []))
        assert_equal sql_status, status.exitstatus, error
        assert_equal ["pg_isready", "sleep"] * (ready_after - 1) + ["pg_isready", "psql"],
          File.readlines(env.fetch("CALL_LOG"), chomp: true)
        assert_equal ["-X", "--set=ON_ERROR_STOP=1", "--file=/bootstrap/bootstrap.sql"],
          File.readlines(env.fetch("PSQL_ARGS"), chomp: true)
      end
    end
  end

  def test_phoenix_has_only_http_and_no_sqlite_or_bundled_postgres
    service = resource(self.class.phoenix, "Service", "phoenix-svc")
    assert_equal "ClusterIP", service.dig("spec", "type")
    assert_equal [6006], service.dig("spec", "ports").map { |p| p["port"] }
    deployment = resource(self.class.phoenix, "Deployment", "phoenix")
    assert_equal "Recreate", deployment.dig("spec", "strategy", "type")
    refute deployment.dig("spec", "strategy").key?("rollingUpdate")
    pod = deployment.dig("spec", "template", "spec")
    refute pod["automountServiceAccountToken"]
    assert_equal [6006], pod.dig("containers", 0, "ports").map { |p| p["containerPort"] }
    assert_equal "true", deployment.dig("spec", "template", "metadata", "labels", "shared-postgres-client")
    refute self.class.phoenix.any? { |d| %w[Secret PersistentVolumeClaim StatefulSet Ingress].include?(d["kind"]) }
  end

  def test_phoenix_auth_and_database_settings
    config = resource(self.class.phoenix, "ConfigMap", "phoenix-configmap").fetch("data")
    %w[PHOENIX_ENABLE_AUTH PHOENIX_USE_SECURE_COOKIES PHOENIX_ENABLE_STRONG_PASSWORD_POLICY].each do |key|
      assert_equal "true", config[key], key
    end
    %w[PHOENIX_ENABLE_MCP_SERVER PHOENIX_ENABLE_MCP_CODE_MODE PHOENIX_ENABLE_PROMETHEUS PHOENIX_TELEMETRY_ENABLED PHOENIX_ENABLE_OAUTH2_AUTHORIZATION_SERVER].each do |key|
      assert_equal "false", config[key], key
    end
    assert_equal "shared-postgres.default.svc.cluster.local", config["PHOENIX_POSTGRES_HOST"]
    assert_equal "phoenix", config["PHOENIX_POSTGRES_USER"]
    assert_equal "phoenix", config["PHOENIX_POSTGRES_DB"]
    assert_equal "7", config["PHOENIX_DEFAULT_RETENTION_POLICY_DAYS"]
    assert_equal "5000", config["PHOENIX_MAX_SPANS_QUEUE_SIZE"]
    env = resource(self.class.phoenix, "Deployment", "phoenix").dig("spec", "template", "spec", "containers", 0, "env")
    assert_equal %w[PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD PHOENIX_POSTGRES_PASSWORD PHOENIX_SECRET], env.map { |e| e["name"] }.sort
    assert env.all? { |e| e.dig("valueFrom", "secretKeyRef", "name") == "phoenix-secret" }
  end

  def test_network_policy_is_scoped_and_http_only
    policy = YAML.load_file("apps/colima/phoenix/networkpolicy.yaml")
    assert_equal({"matchLabels" => {"app" => "phoenix"}}, policy.dig("spec", "podSelector"))
    assert_equal [6006], policy.dig("spec", "ingress").flat_map { |r| r["ports"].map { |p| p["port"] } }
    assert_equal "ingress-nginx", policy.dig("spec", "ingress", 0, "from", 0, "namespaceSelector", "matchLabels", "kubernetes.io/metadata.name")
    assert_equal [53, 53, 5432], policy.dig("spec", "egress").flat_map { |r| r["ports"].map { |p| p["port"] } }.sort
    postgres = resource(self.class.postgres, "NetworkPolicy", "shared-postgres")
    assert_equal "true", postgres.dig("spec", "ingress", 0, "from", 0, "podSelector", "matchLabels", "shared-postgres-client")
    assert_equal [], postgres.dig("spec", "egress")
  end

  def test_gitops_registration_dependency_and_colima_size
    apps = self.class.docs(self.class.command("kubectl", "kustomize", "apps/colima"))
    %w[phoenix shared-postgres].each do |name|
      release = resource(apps, "HelmRelease", name)
      assert_equal "default", release.dig("metadata", "namespace")
    end
    phoenix = resource(apps, "HelmRelease", "phoenix")
    assert_equal [{"name" => "shared-postgres"}], phoenix.dig("spec", "dependsOn")
    infrastructure = self.class.docs(self.class.command("kubectl", "kustomize", "infrastructure/colima"))
    source = resource(infrastructure, "OCIRepository", "phoenix")
    assert_match(/\Asha256:[a-f0-9]{64}\z/, source.dig("spec", "ref", "digest"))
    assert_equal "copy", source.dig("spec", "layerSelector", "operation")
    config = YAML.load_file("config/colima/values.yaml")
    assert_equal 4, config["cpu"]
    assert_equal 12, config["memory"]
    assert_equal 100, config["disk"]
  end

  def with_fake_kubectl
    Dir.mktmpdir("phoenix-secrets-test-") do |dir|
      # This executable stores only newly generated test credentials in a temp dir.
      # No invocation in these tests can reach a Kubernetes cluster.
      fake = File.join(dir, "kubectl")
      File.write(fake, <<~'RUBY')
        #!/usr/bin/env ruby
        require "json"
        dir = ENV.fetch("FAKE_KUBE_DIR")
        case ARGV.fetch(4)
        when "get"
          name = ARGV.fetch(6)
          path = File.join(dir, "#{name}.json")
          if File.exist?(path)
            puts(ARGV.last == "name" ? "secret/#{name}" : File.read(path))
          elsif !ARGV.include?("--ignore-not-found")
            abort "Secret not found"
          end
        when "create"
          doc = JSON.parse(STDIN.read)
          name = doc.dig("metadata", "name")
          File.write(File.join(dir, "#{name}.json"), JSON.generate(doc))
          puts "secret/#{name} created"
        else
          abort "Unexpected fake kubectl command"
        end
      RUBY
      File.chmod(0o755, fake)
      env = {"PATH" => "#{dir}:#{ENV.fetch("PATH")}", "FAKE_KUBE_DIR" => dir,
             "KUBE_CONTEXT" => "test-only-no-cluster"}
      yield dir, env
    end
  end

  def test_secret_creation_is_strong_idempotent_and_does_not_print_values
    with_fake_kubectl do |dir, env|
      output, error, status = Open3.capture3(env, "bash", "scripts/phoenix-secrets.sh")
      assert status.success?, error
      paths = Dir.glob(File.join(dir, "*.json")).sort
      assert_equal 2, paths.size
      paths.each do |path|
        JSON.parse(File.read(path)).fetch("data").each do |key, encoded|
          value = Base64.strict_decode64(encoded)
          assert_operator value.length, :>=, 32, key
          refute_includes output + error, value
          assert value.match?(/[a-z]/) && value.match?(/[A-Z]/) &&
                 value.match?(/[0-9]/) && value.match?(/[^a-zA-Z0-9]/)
        end
      end
      hashes = paths.map { |path| Digest::SHA256.file(path).hexdigest }
      output, error, status = Open3.capture3(env, "bash", "scripts/phoenix-secrets.sh")
      assert status.success?, error
      assert_includes output, "Reusing default/phoenix-secret"
      assert_equal hashes, paths.map { |path| Digest::SHA256.file(path).hexdigest }
    end
  end

  def test_incomplete_existing_secret_is_not_overwritten
    with_fake_kubectl do |dir, env|
      path = File.join(dir, "shared-postgres-auth.json")
      File.write(path, JSON.generate({"data" => {"POSTGRES_PASSWORD" => Base64.strict_encode64("invalid")}}))
      before = Digest::SHA256.file(path).hexdigest
      _, error, status = Open3.capture3(env, "bash", "scripts/phoenix-secrets.sh")
      refute status.success?
      assert_includes error, "Existing Secret is missing/invalid"
      assert_equal before, Digest::SHA256.file(path).hexdigest
      refute File.exist?(File.join(dir, "phoenix-secret.json"))
    end
  end
end
