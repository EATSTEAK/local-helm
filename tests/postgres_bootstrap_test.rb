require "minitest/autorun"
require "open3"
require "securerandom"
require "yaml"

class PostgresBootstrapTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ADMIN_PASSWORD = "test-only-admin-password-aA1!"
  APP_PASSWORD = "test-only-quoted-'password-aA1!"

  def self.capture(*args, input: "")
    Open3.capture3(*args, stdin_data: input)
  end

  def self.container
    return @container if @container
    name = "phoenix-pr-test-#{SecureRandom.hex(6)}"
    image = YAML.load_file(File.join(ROOT, "apps/colima/shared-postgres/values.yaml")).fetch("image")
    _, error, status = capture("docker", "run", "--detach", "--name", name,
      "--memory", "512m", "--cpus", "0.5", "--read-only", "--user", "999:999",
      "--tmpfs", "/var/lib/postgresql/data:rw,uid=999,gid=999,mode=0700,size=256m",
      "--tmpfs", "/var/run/postgresql:rw,uid=999,gid=999,mode=0700,size=16m",
      "--tmpfs", "/tmp:rw,uid=999,gid=999,mode=0700,size=32m",
      "--env", "PGDATA=/var/lib/postgresql/data/pgdata",
      "--env", "POSTGRES_PASSWORD=#{ADMIN_PASSWORD}",
      "--env", "POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256 --auth-local=peer",
      "#{image.fetch("repository")}@#{image.fetch("digest")}",
      "postgres", "-c", "shared_buffers=128MB", "-c", "max_connections=50",
      "-c", "autovacuum_work_mem=32MB", "-c", "max_wal_size=512MB")
    raise "Could not start isolated test DB: #{error}" unless status.success?
    @container = name
    Minitest.after_run do
      # Exact randomly named test container; data is tmpfs, no user PVC/volume.
      capture("docker", "rm", "--force", name)
    end
    60.times do
      _, _, ready = capture("docker", "exec", name, "pg_isready", "-h", "127.0.0.1", "-U", "postgres")
      return @container if ready.success?
      sleep 0.5
    end
    raise "Isolated test DB did not become ready"
  end

  def sql(statement)
    output, error, status = self.class.capture("docker", "exec", self.class.container,
      "psql", "-X", "-U", "postgres", "-d", "postgres", "-At", "-c", statement)
    assert status.success?, error
    output.strip
  end

  def bootstrap(database, owner = database)
    self.class.capture("docker", "exec", "-i",
      "--env", "PGHOST=127.0.0.1", "--env", "PGUSER=postgres", "--env", "PGDATABASE=postgres",
      "--env", "PGPASSWORD=#{ADMIN_PASSWORD}",
      "--env", "APP_DATABASE=#{database}", "--env", "APP_OWNER=#{owner}",
      "--env", "APP_CONNECTION_LIMIT=20", "--env", "APP_PASSWORD=#{APP_PASSWORD}",
      self.class.container, "psql", "-X", "--set=ON_ERROR_STOP=1",
      input: File.read(File.join(ROOT, "charts/shared-postgres/files/bootstrap.sql")))
  end

  def app_sql(database, statement)
    self.class.capture("docker", "exec", "--env", "PGPASSWORD=#{APP_PASSWORD}", self.class.container,
      "psql", "-X", "-h", "127.0.0.1", "-U", "phoenix", "-d", database,
      "--set=ON_ERROR_STOP=1", "-At", "-c", statement)
  end

  def test_creation_authentication_idempotence_and_isolation
    output, error, status = bootstrap("phoenix")
    assert status.success?, error
    refute_includes output + error, APP_PASSWORD
    assert_equal "f|f|f|f|f|20", sql("SELECT rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls,rolconnlimit FROM pg_roles WHERE rolname='phoenix'")
    output, error, status = app_sql("phoenix", "CREATE TABLE smoke(id integer); INSERT INTO smoke VALUES (42); SELECT id FROM smoke;")
    assert status.success?, error
    assert_includes output, "42"
    _, error, status = bootstrap("phoenix")
    assert status.success?, error
    output, error, status = app_sql("phoenix", "SELECT id FROM smoke;")
    assert status.success?, error
    assert_equal "42", output.strip
    _, error, status = bootstrap("other_app")
    assert status.success?, error
    %w[postgres template1 other_app].each do |database|
      _, _, status = app_sql(database, "SELECT 1;")
      refute status.success?, "phoenix must not connect to #{database}"
    end
    _, _, status = app_sql("phoenix", "CREATE ROLE forbidden_role;")
    refute status.success?
  end

  def test_refuses_privileged_role
    sql("CREATE ROLE unsafe_app SUPERUSER LOGIN;")
    _, error, status = bootstrap("unsafe_app")
    refute status.success?
    assert_includes error, "Refusing to adopt a privileged application role"
    assert_equal "0", sql("SELECT count(*) FROM pg_database WHERE datname='unsafe_app'")
  end

  def test_refuses_foreign_database_owner
    sql("CREATE DATABASE foreign_db;")
    _, error, status = bootstrap("foreign_db", "foreign_user")
    refute status.success?
    assert_includes error, "Refusing to adopt a database owned by another role"
  end
end
