require "minitest/autorun"
require "yaml"
require "open3"

ROOT = File.expand_path("..", __dir__)
Dir.chdir(ROOT)

class FlamresConfigurationTest < Minitest::Test
  def documents(*command)
    output, error, status = Open3.capture3(*command)
    assert status.success?, error
    YAML.load_stream(output).compact
  end

  def setup
    @rendered = documents("helm", "template", "flamres", "charts/flamres", "-n", "flamres",
      "-f", "apps/colima/flamres/values.yaml")
  end

  def test_pi_configuration_preserves_the_opencode_rollback_and_existing_state
    config = @rendered.find { |d| d["kind"] == "ConfigMap" }.fetch("data")
    state = "/home/node/.local/share/triflam-bot"
    assert_equal "triflam-local/gpt-5.6-terra", config["PI_MODEL"]
    assert_equal "http://host.docker.internal:8317/v1", config["PI_PROVIDER_BASE_URL"]
    assert_equal "/app/.pi", config["PI_BUNDLED_RESOURCES_DIR"]
    assert_equal "/workspace", config["PI_WORKDIR"]
    assert_equal "1800000", config["PI_PROMPT_TIMEOUT_MS"]
    assert_equal "128000", config["PI_MODEL_CONTEXT_WINDOW"]
    assert_equal "16384", config["PI_MODEL_MAX_TOKENS"]
    {"PI_AGENT_DIR" => "pi-agent", "PI_SESSION_DIR" => "pi-sessions",
     "PI_THREAD_SESSION_STORE_PATH" => "pi-thread-sessions.json", "THREAD_SESSION_STORE_PATH" => "thread-sessions.json",
     "SCHEDULE_STORE_PATH" => "schedules.json", "NOTION_CALENDAR_SYNC_STORE_PATH" => "notion-calendar-sync.json",
     "SLACK_BLOCKS_DIR" => "slack-blocks"}.each do |key, file|
      assert_equal "#{state}/#{file}", config[key], key
    end
    assert_equal config["PI_MODEL"], config["OPENCODE_MODEL"]
    assert_equal config["PI_PROVIDER_BASE_URL"], config["OPENCODE_PROVIDER_BASE_URL"]
    assert_equal "/app/.opencode", config["OPENCODE_BUNDLED_CONFIG_DIR"]
    assert_equal "/workspace", config["OPENCODE_WORKDIR"]
    assert_equal "4097", config["OPENCODE_SERVER_PORT"]
    %w[PI_API_KEY OPENCODE_API_KEY LINEAR_API_KEY MCP_LINEAR_ENABLED MCP_LINEAR_URL].each do |key|
      refute config.key?(key), key
    end
    refute @rendered.any? { |d| d["kind"] == "Secret" }
  end

  def test_health_probes_use_process_liveness_and_agent_readiness
    pod = @rendered.find { |d| d["kind"] == "Deployment" }.dig("spec", "template", "spec")
    container = pod.fetch("containers").first
    {"startupProbe" => ["/health/ready", 5, 12], "readinessProbe" => ["/health/ready", 5, 3],
     "livenessProbe" => ["/health/live", 10, 3]}.each do |name, (path, period, threshold)|
      probe = container.fetch(name)
      assert_equal({"path" => path, "port" => "http"}, probe["httpGet"])
      assert_equal period, probe["periodSeconds"]
      assert_equal 2, probe["timeoutSeconds"]
      assert_equal threshold, probe["failureThreshold"]
    end
    assert_includes container["envFrom"], {"configMapRef" => {"name" => "flamres-config"}}
    assert_includes container["envFrom"], {"secretRef" => {"name" => "flamres-secrets"}}
    assert_equal ["http"], container.fetch("ports").map { |port| port["name"] }
  end

  def test_gitops_keeps_both_existing_pvcs_and_their_mounts
    claims = %w[flamres-opencode-data flamres-workdir]
    deployment = @rendered.find { |d| d["kind"] == "Deployment" }
    assert_equal 1, deployment.dig("spec", "replicas")
    assert_equal({"type" => "Recreate"}, deployment.dig("spec", "strategy"))
    pod = deployment.dig("spec", "template", "spec")
    assert_equal claims, pod.fetch("volumes").map { |v| v.dig("persistentVolumeClaim", "claimName") }.sort
    mounts = pod.fetch("containers").first.fetch("volumeMounts").to_h { |v| [v["name"], v["mountPath"]] }
    assert_equal({"opencode-data" => "/home/node/.local", "opencode-workdir" => "/workspace"}, mounts)
    refute @rendered.any? { |d| d["kind"] == "PersistentVolumeClaim" }
    overlay = documents("kubectl", "kustomize", "apps/colima/flamres")
    assert_equal claims, overlay.select { |d| d["kind"] == "PersistentVolumeClaim" }.map { |d| d.dig("metadata", "name") }.sort
    values = overlay.find { |d| d["kind"] == "ConfigMap" && d.dig("metadata", "name") == "flamres-values" }
    assert_equal YAML.load_file("apps/colima/flamres/values.yaml"), YAML.safe_load(values.dig("data", "values.yaml"))
    refute overlay.any? { |d| d["kind"] == "Secret" }
  end
end
