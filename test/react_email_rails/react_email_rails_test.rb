require("test_helper")

class ReactEmailRailsTest < ActiveSupport::TestCase
  RUBY = RbConfig.ruby

  RENDER_FIXED = [
    RUBY,
    "-e",
    'require "json"; $stdin.read; $stdout.write(JSON.generate(html: "<p>Hi</p>", text: "Hi"))',
  ].freeze

  HEALTH_OK = [
    RUBY,
    "-e",
    'require "json"; $stdout.write(JSON.generate(ok: true)) if ARGV.include?("--health")',
    "--",
  ].freeze

  PERSISTENT_HEALTH_OK = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      abort "wrong mode" unless ARGV.include?("--persistent") && !ARGV.include?("--health")
      request = JSON.parse($stdin.gets)
      $stdout.puts(JSON.generate(ok: request["health"] == true))
      $stdout.flush
    RUBY
    "--",
  ].freeze

  test("render emits a render.react-email-rails notification with component and html size") do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("render.react-email-rails") { |event| events << event }

    with_react_email_config(render_command: RENDER_FIXED, cache: false) do
      ReactEmailRails.render(component: "users/welcome", props: {})
    end

    payload = events.sole.payload
    assert_equal("users/welcome", payload[:component])
    assert_equal("<p>Hi</p>".bytesize, payload[:html_bytes])
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test("render invokes on_render_error and re-raises on failure") do
    reported = []

    with_react_email_config(
      render_command: [RUBY, "-e", "exit 1"],
      cache: false,
      on_render_error: ->(error, component:) { reported << [error, component] },
    ) do
      assert_raises(ReactEmailRails::RenderError) do
        ReactEmailRails.render(component: "users/welcome", props: {})
      end
    end

    error, component = reported.sole
    assert_instance_of(ReactEmailRails::RenderError, error)
    assert_equal("users/welcome", component)
  end

  test("healthy? returns true when the command reports ok") do
    with_react_email_config(render_command: HEALTH_OK) do
      assert(ReactEmailRails.healthy?)
    end
  end

  test("healthy? uses the persistent render mode protocol when configured") do
    with_react_email_config(render_command: PERSISTENT_HEALTH_OK, render_mode: :persistent) do
      assert(ReactEmailRails.healthy?)
    end
  ensure
    ReactEmailRails::RenderModes::Persistent::CommandRunner.stop_all
  end

  test("healthy? returns false when the command fails") do
    with_react_email_config(render_command: [RUBY, "-e", "exit 1"]) do
      assert_not(ReactEmailRails.healthy?)
    end
  end

  test("healthy? returns false when the command times out") do
    with_react_email_config(render_command: [RUBY, "-e", "sleep 5"], render_timeout: 0.1) do
      assert_not(ReactEmailRails.healthy?)
    end
  end
end
