require("test_helper")
require("fileutils")
require("rake")

class ReactEmailRails::TasksTest < ActiveSupport::TestCase
  test("build runs the package build command") do
    Dir.mktmpdir do |dir|
      marker = File.join(dir, "built")
      cwd_marker = File.join(dir, "cwd")
      bundle = File.join(dir, "emails.js")
      command = File.join(dir, "react-email-rails-build")
      File.write(command, "#!/usr/bin/env ruby\nFile.write(#{marker.inspect}, \"ok\")\nFile.write(#{cwd_marker.inspect}, Dir.pwd)\nFile.write(#{bundle.inspect}, \"bundle\")\n")
      FileUtils.chmod("+x", command)

      Dir.chdir(dir) do
        with_task_paths(command:, bundle:) { ReactEmailRails::Tasks.build }
      end

      assert_equal("ok", File.read(marker))
      assert_equal(Rails.root.to_s, File.read(cwd_marker))
      assert_equal("bundle", File.read(bundle))
    end
  end

  test("build is not skipped when explicitly invoked with the skip environment variable") do
    Dir.mktmpdir do |dir|
      bundle = File.join(dir, "emails.js")
      command = File.join(dir, "react-email-rails-build")
      File.write(command, "#!/usr/bin/env ruby\nFile.write(#{bundle.inspect}, \"bundle\")\n")
      FileUtils.chmod("+x", command)

      with_env("SKIP_REACT_EMAIL_RAILS_BUILD" => "1") do
        with_task_paths(command:, bundle:) { ReactEmailRails::Tasks.build }
      end

      assert_equal("bundle", File.read(bundle))
    end
  end

  test("build raises when the bundle is not produced") do
    Dir.mktmpdir do |dir|
      bundle = File.join(dir, "emails.js")
      command = File.join(dir, "react-email-rails-build")
      File.write(command, "#!/usr/bin/env ruby\n")
      FileUtils.chmod("+x", command)

      error = assert_raises(RuntimeError) do
        with_task_paths(command:, bundle:) { ReactEmailRails::Tasks.build }
      end

      assert_includes(error.message, "email bundle was not found")
    end
  end

  test("automatic hooks can be skipped with an environment variable") do
    with_env("SKIP_REACT_EMAIL_RAILS_BUILD" => "1") do
      with_isolated_rake_application do
        Rake::Task.define_task("assets:precompile")

        Rails.application.load_tasks

        assert_empty(Rake::Task["assets:precompile"].prerequisites)
      end
    end
  end

  test("build raises when the package build command is missing") do
    error = assert_raises(RuntimeError) do
      with_task_paths(command: "/does/not/exist", bundle: "/does/not/exist") { ReactEmailRails::Tasks.build }
    end

    assert_includes(error.message, "react-email-rails build command not found")
  end

  test("railtie hooks the build task into Rails build tasks") do
    with_isolated_rake_application do
      Rake::Task.define_task("assets:precompile")
      Rake::Task.define_task("assets:clobber")

      Rails.application.load_tasks

      assert_includes(Rake::Task["assets:precompile"].prerequisites, "react_email_rails:build")
      assert_includes(Rake::Task["assets:clobber"].prerequisites, "react_email_rails:clobber")
    end
  end

  test("railtie defines Rails asset tasks when no asset pipeline has defined them") do
    with_isolated_rake_application do
      Rails.application.load_tasks

      assert_includes(Rake::Task["assets:precompile"].prerequisites, "react_email_rails:build")
      assert_includes(Rake::Task["assets:clobber"].prerequisites, "react_email_rails:clobber")
    end
  end

  private

  def with_task_paths(command:, bundle:)
    singleton = class << ReactEmailRails::Tasks; self; end
    original_build_command = ReactEmailRails::Tasks.method(:build_command)
    original_bundle_path = ReactEmailRails::Tasks.method(:bundle_path)
    singleton.remove_method(:build_command)
    singleton.remove_method(:bundle_path)
    singleton.define_method(:build_command) { command }
    singleton.define_method(:bundle_path) { bundle }
    singleton.send(:private, :build_command)
    singleton.send(:private, :bundle_path)
    yield
  ensure
    singleton.remove_method(:build_command)
    singleton.remove_method(:bundle_path)
    singleton.define_method(:build_command) { original_build_command.call }
    singleton.define_method(:bundle_path) { original_bundle_path.call }
    singleton.send(:private, :build_command)
    singleton.send(:private, :bundle_path)
  end

  def with_env(values)
    original = values.to_h { |key, _| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def with_isolated_rake_application
    original_application = Rake.application
    original_loaded = Rails.application.instance_variable_get(:@rake_tasks_loaded)
    original_verbose = $VERBOSE
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    Rails.application.instance_variable_set(:@rake_tasks_loaded, false)
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = original_verbose
    Rails.application.instance_variable_set(:@rake_tasks_loaded, original_loaded)
    Rake.application = original_application
  end
end
