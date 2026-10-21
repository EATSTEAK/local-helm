require "minitest/autorun"
require "yaml"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)

class ColimaImageGCTest < Minitest::Test
  KUBELET_DIR = "/var/lib/rancher/k3s/agent/etc/kubelet.conf.d"
  EXPECTED = {
    "apiVersion" => "kubelet.config.k8s.io/v1beta1",
    "kind" => "KubeletConfiguration",
    "imageMaximumGCAge" => "24h"
  }.freeze

  def setup
    config = YAML.load_file(File.join(ROOT, "config/colima/values.yaml"))
    provisions = config.fetch("provision").select { |p| p.fetch("script").include?("10-image-gc.conf") }
    assert_equal 1, provisions.length
    assert_equal "system", provisions.first.fetch("mode")
    @script = provisions.first.fetch("script")
    assert_includes @script, KUBELET_DIR
  end

  def test_provision_script_is_valid_shell
    _, error, status = Open3.capture3("sh", "-n", stdin_data: @script)
    assert status.success?, error
  end

  def test_installs_and_updates_only_the_gc_drop_in
    Dir.mktmpdir("colima-gc test-") do |dir|
      config_dir = File.join(dir, "kubelet.conf.d")
      # Redirect only the VM path; execute the real provision script without a VM or sudo.
      script = @script.gsub(KUBELET_DIR, config_dir)
      target = File.join(config_dir, "10-image-gc.conf")
      3.times do |attempt|
        if attempt == 1
          File.write(File.join(config_dir, "00-k3s-defaults.conf"), "k3s defaults\n")
          File.write(File.join(config_dir, "20-custom.conf"), "user settings\n")
          File.write(target, EXPECTED.merge("imageMaximumGCAge" => "48h").to_yaml)
        end
        _, error, status = Open3.capture3("sh", "-c", "umask 077\n#{script}")
        assert status.success?, error
        assert_equal EXPECTED, YAML.load_file(target)
        assert_equal 0o644, File.stat(target).mode & 0o777
      end
      assert_equal "k3s defaults\n", File.read(File.join(config_dir, "00-k3s-defaults.conf"))
      assert_equal "user settings\n", File.read(File.join(config_dir, "20-custom.conf"))
      assert_equal %w[00-k3s-defaults.conf 10-image-gc.conf 20-custom.conf], Dir.children(config_dir).sort
    end
  end

  def test_failed_install_preserves_previous_config_and_removes_temporary_files
    %w[mktemp chmod mv].each do |command|
      Dir.mktmpdir("colima-gc-failure-") do |dir|
        config_dir = File.join(dir, "kubelet.conf.d")
        Dir.mkdir(config_dir)
        target = File.join(config_dir, "10-image-gc.conf")
        previous = EXPECTED.merge("imageMaximumGCAge" => "48h").to_yaml
        File.write(target, previous)
        bin = File.join(dir, "bin")
        Dir.mkdir(bin)
        fake = File.join(bin, command)
        File.write(fake, "#!/bin/sh\nexit 1\n")
        File.chmod(0o755, fake)
        env = {"PATH" => "#{bin}:#{ENV.fetch("PATH")}"}
        _, _, status = Open3.capture3(env, "sh", "-c", @script.gsub(KUBELET_DIR, config_dir))
        refute status.success?, "Must report #{command} failure"
        assert_equal previous, File.read(target)
        assert_equal ["10-image-gc.conf"], Dir.children(config_dir)
      end
    end
  end
end
