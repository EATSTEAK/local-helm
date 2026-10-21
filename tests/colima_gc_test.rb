require "minitest/autorun"
require "yaml"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)

class ColimaRetentionTest < Minitest::Test
  JOURNAL_FILE = "60-local-helm-retention.conf"
  DROP_INS = {
    "10-image-gc.conf" => ["/var/lib/rancher/k3s/agent/etc/kubelet.conf.d", <<~YAML],
      apiVersion: kubelet.config.k8s.io/v1beta1
      kind: KubeletConfiguration
      imageMaximumGCAge: 24h
    YAML
    JOURNAL_FILE => ["/etc/systemd/journald.conf.d", <<~INI]
      [Journal]
      SystemMaxUse=1G
      SystemKeepFree=1G
      MaxRetentionSec=7day
    INI
  }.freeze

  def setup
    @config = YAML.load_file(File.join(ROOT, "config/colima/values.yaml"))
  end

  def with_provision(name)
    directory, = DROP_INS.fetch(name)
    provisions = @config.fetch("provision").select { |p| p.fetch("script").include?(name) }
    assert_equal 1, provisions.length
    assert_equal "system", provisions.first.fetch("mode")
    script = provisions.first.fetch("script")
    assert_includes script, directory
    Dir.mktmpdir("colima-retention test-") do |dir|
      bin = File.join(dir, "bin")
      Dir.mkdir(bin)
      # Never restart a real service, including on the Linux CI runner.
      fake = File.join(bin, "systemctl")
      File.write(fake, <<~'SH')
        #!/bin/sh
        printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
        exit "${SYSTEMCTL_STATUS:-0}"
      SH
      File.chmod(0o755, fake)
      env = {"PATH" => "#{bin}:#{ENV.fetch("PATH")}",
             "SYSTEMCTL_LOG" => File.join(dir, "systemctl.log"), "SYSTEMCTL_STATUS" => "0"}
      config_dir = File.join(dir, "conf.d")
      # Redirect only the VM path and execute the actual provision script.
      yield script.gsub(directory, config_dir), config_dir, env
    end
  end

  def test_docker_logging_and_builder_gc_policy
    assert_equal "docker", @config.fetch("runtime")
    assert_equal({
      "log-driver" => "json-file",
      "log-opts" => {"max-size" => "5m", "max-file" => "3"},
      "builder" => {"gc" => {"enabled" => true, "defaultKeepStorage" => "5GB"}}
    }, @config.fetch("docker"))
  end

  def test_provision_scripts_are_valid_shell
    DROP_INS.each_key do |name|
      with_provision(name) do |script, _, _|
        _, error, status = Open3.capture3("sh", "-n", stdin_data: script)
        assert status.success?, error
      end
    end
  end

  def test_installs_and_updates_only_the_owned_drop_ins
    DROP_INS.each do |name, (_, expected)|
      with_provision(name) do |script, config_dir, env|
        target = File.join(config_dir, name)
        3.times do |attempt|
          if attempt == 1
            File.write(File.join(config_dir, "00-existing.conf"), "unrelated settings\n")
            File.write(target, "previous settings\n")
          end
          _, error, status = Open3.capture3(env, "sh", "-c", "umask 077\n#{script}")
          assert status.success?, error
          assert_equal expected, File.read(target)
          assert_equal 0o644, File.stat(target).mode & 0o777
        end
        assert_equal "unrelated settings\n", File.read(File.join(config_dir, "00-existing.conf"))
        assert_equal ["00-existing.conf", name].sort, Dir.children(config_dir).sort
        calls = File.exist?(env.fetch("SYSTEMCTL_LOG")) ? File.readlines(env.fetch("SYSTEMCTL_LOG"), chomp: true) : []
        assert_equal(name == JOURNAL_FILE ? ["restart systemd-journald.service"] * 3 : [], calls)
      end
    end
  end

  def test_failed_write_preserves_previous_config_and_removes_temporary_files
    DROP_INS.each_key do |name|
      %w[mkdir mktemp chmod mv].each do |command|
        with_provision(name) do |script, config_dir, env|
          Dir.mkdir(config_dir)
          target = File.join(config_dir, name)
          File.write(target, "previous settings\n")
          fake = File.join(File.dirname(config_dir), "bin", command)
          File.write(fake, "#!/bin/sh\nexit 1\n")
          File.chmod(0o755, fake)
          _, _, status = Open3.capture3(env, "sh", "-c", script)
          refute status.success?, "Must report #{command} failure"
          assert_equal "previous settings\n", File.read(target)
          assert_equal [name], Dir.children(config_dir)
          refute File.exist?(env.fetch("SYSTEMCTL_LOG")), "Do not restart after a failed config write"
        end
      end
    end
  end

  def test_journal_restart_failure_is_reported_and_retry_reapplies_config
    with_provision(JOURNAL_FILE) do |script, config_dir, env|
      _, _, status = Open3.capture3(env.merge("SYSTEMCTL_STATUS" => "1"), "sh", "-c", script)
      refute status.success?
      assert_equal DROP_INS.fetch(JOURNAL_FILE).last, File.read(File.join(config_dir, JOURNAL_FILE))
      _, error, status = Open3.capture3(env, "sh", "-c", script)
      assert status.success?, error
      assert_equal ["restart systemd-journald.service"] * 2,
        File.readlines(env.fetch("SYSTEMCTL_LOG"), chomp: true)
      assert_equal [JOURNAL_FILE], Dir.children(config_dir)
    end
  end
end
