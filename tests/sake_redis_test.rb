require "minitest/autorun"
require "open3"
require "yaml"

class SakeRedisTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def render(*options)
    output, error, status = Open3.capture3("helm", "template", "sake-deps",
      File.join(ROOT, "charts/sake-deps"), "--namespace", "sake", *options)
    assert status.success?, error
    YAML.load_stream(output).compact.select do |resource|
      resource.dig("metadata", "labels", "app.kubernetes.io/component") == "redis"
    end
  end

  def test_persistence_configuration_for_pod_replacement
    resources = render
    deployment = resources.find { |resource| resource["kind"] == "Deployment" }
    claim = resources.find { |resource| resource["kind"] == "PersistentVolumeClaim" }
    pod = deployment.dig("spec", "template", "spec")
    redis = pod.fetch("containers").first
    assert_equal "Recreate", deployment.dig("spec", "strategy", "type")
    assert_equal ["--appendonly", "yes", "--appendfsync", "everysec"], redis.fetch("args")
    assert_equal [{ "name" => "data", "mountPath" => "/data" }], redis.fetch("volumeMounts")
    assert_equal claim.dig("metadata", "name"), pod.fetch("volumes").first.dig("persistentVolumeClaim", "claimName")
    assert_equal "keep", claim.dig("metadata", "annotations", "helm.sh/resource-policy")
  end

  def test_ephemeral_override_has_no_persistent_storage
    resources = render("--set", "redis.persistence.enabled=false")
    refute resources.any? { |resource| resource["kind"] == "PersistentVolumeClaim" }
    pod = resources.find { |resource| resource["kind"] == "Deployment" }.dig("spec", "template", "spec")
    assert_nil pod["volumes"]
    assert_nil pod.fetch("containers").first["volumeMounts"]
    assert_nil pod.fetch("containers").first["args"]
  end
end
