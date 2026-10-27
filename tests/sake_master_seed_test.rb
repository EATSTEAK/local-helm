require "minitest/autorun"
require "yaml"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
Dir.chdir(ROOT)

class SakeMasterSeedTest < Minitest::Test
  def setup
    output, error, status = Open3.capture3("helm", "template", "sake", "charts/sake-api",
      "-n", "sake", "-f", "apps/colima/sake/api-values.yaml")
    assert status.success?, error
    job = YAML.load_stream(output).compact.find do |document|
      document["kind"] == "Job" && document.dig("metadata", "labels", "app.kubernetes.io/component") == "master-seed"
    end
    refute_nil job, "Rendered chart must include the master seed job"
    @container = job.dig("spec", "template", "spec", "containers").first
  end

  def run_seed(environment)
    Dir.mktmpdir("sake-master-seed-test-") do |dir|
      log = File.join(dir, "node-calls")
      node = File.join(dir, "node")
      File.write(node, "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$NODE_CALL_LOG\"\n")
      File.chmod(0o755, node)
      env = {"PATH" => dir, "NODE_CALL_LOG" => log}.merge(environment)
      _, error, status = Open3.capture3(env, *@container.fetch("command"), unsetenv_others: true)
      [status, File.exist?(log) ? File.readlines(log, chomp: true) : [], error]
    end
  end

  def test_canonical_credentials_seed_without_legacy_names
    status, calls, error = run_seed(
      "DATABASE_URL" => "postgres://test/db",
      "ADMIN_EMAIL" => "admin@example.test",
      "ADMIN_PASSWORD" => "test-password"
    )

    assert status.success?, error
    assert_equal ["server/api/dist/auth/seed-master-account.js"], calls
  end

  def test_missing_or_empty_required_values_stop_before_seed
    required = %w[DATABASE_URL ADMIN_EMAIL ADMIN_PASSWORD]
    required.each do |missing_key|
      environment = {"DATABASE_URL" => "postgres://test/db", "ADMIN_EMAIL" => "admin@example.test",
                     "ADMIN_PASSWORD" => "test-password"}
      environment.delete(missing_key)
      status, calls, = run_seed(environment)
      refute status.success?, "Missing #{missing_key} must fail"
      assert_empty calls, "Missing #{missing_key} must not invoke the seed script"

      status, calls, = run_seed(environment.merge(missing_key => ""))
      refute status.success?, "Empty #{missing_key} must fail"
      assert_empty calls, "Empty #{missing_key} must not invoke the seed script"
    end
  end

  def test_legacy_only_credentials_do_not_satisfy_canonical_inputs
    status, calls, = run_seed(
      "DATABASE_URL" => "postgres://test/db",
      "SAKE_ADMIN_EMAIL" => "admin@example.test",
      "SAKE_ADMIN_PASSWORD" => "test-password"
    )

    refute status.success?, "Legacy names must not satisfy the canonical credential checks"
    assert_empty calls
  end
end
