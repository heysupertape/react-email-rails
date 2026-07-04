require("json")
require("test_helper")

class ReactEmailRailsTest < ActiveSupport::TestCase
  RENDER_FIXED = [
    RUBY,
    "-e",
    "require \"json\"; $stdin.read; $stdout.write(JSON.generate(html: \"<p>Hi</p>\", text: \"Hi\", #{RENDER_METADATA}))",
  ].freeze

  HEALTH_OK = [
    RUBY,
    "-e",
    "require \"json\"; $stdout.write(JSON.generate(ok: true, #{RENDER_METADATA})) if ARGV.include?(\"--health\")",
    "--",
  ].freeze

  PERSISTENT_HEALTH_OK = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      abort "wrong mode" unless ARGV.include?("--persistent") && !ARGV.include?("--health")
      request = JSON.parse($stdin.gets)
      $stdout.puts(JSON.generate(ok: request["health"] == true, #{RENDER_METADATA}))
      $stdout.flush
    RUBY
    "--",
  ].freeze

  # stop_all is idempotent; tear down any persistent child unconditionally.
  teardown { ReactEmailRails::RenderModes::Persistent::CommandRunner.stop_all }

  test("render emits a render.react-email-rails notification with component and html size") do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("render.react-email-rails") { |event| events << event }

    with_react_email_internals(render_command: RENDER_FIXED) do
      ReactEmailRails.render(component: "users/welcome", props: {})
    end

    payload = events.sole.payload
    assert_equal("users/welcome", payload[:component])
    assert_equal("<p>Hi</p>".bytesize, payload[:html_bytes])
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test("render serializes props and camelizes keys before sending them") do
    rendered = with_react_email_internals(render_command: ECHO_INPUT) do
      ReactEmailRails.render(
        component: "users/welcome",
        props: {
          account_name: "Ada",
          nested_props: { owner_email: "ada@example.com", tags: [{ created_at: "today" }] },
        },
      )
    end

    assert_equal(
      {
        "component" => "users/welcome",
        "props" => {
          "accountName" => "Ada",
          "nestedProps" => { "ownerEmail" => "ada@example.com", "tags" => [{ "createdAt" => "today" }] },
        },
      },
      JSON.parse(rendered.html),
    )
  end

  test("render can send props without camelizing keys") do
    rendered = with_react_email_internals(render_command: ECHO_INPUT) do
      with_react_email_config(transform_props: :none) do
        ReactEmailRails.render(
          component: "users/welcome",
          props: { account_name: "Ada", nested_props: { owner_email: "ada@example.com" } },
        )
      end
    end

    assert_equal(
      { "account_name" => "Ada", "nested_props" => { "owner_email" => "ada@example.com" } },
      JSON.parse(rendered.html).fetch("props"),
    )
  end

  test("render invokes on_render_error with a uniform context and re-raises on failure") do
    reported = []

    with_react_email_internals(render_command: [RUBY, "-e", "exit 1"]) do
      with_react_email_config(
        on_render_error: ->(error, **context) { reported << [error, context] },
      ) do
        assert_raises(ReactEmailRails::RenderError) do
          ReactEmailRails.render(component: "users/welcome", props: {})
        end
      end
    end

    error, context = reported.sole
    assert_instance_of(ReactEmailRails::RenderError, error)
    assert_equal({ component: "users/welcome" }, context)
  end

  test("healthy? returns true when the command reports ok") do
    with_react_email_internals(render_command: HEALTH_OK) do
      assert(ReactEmailRails.healthy?)
    end
  end

  test("healthy? uses the persistent render mode protocol when configured") do
    with_react_email_internals(render_command: PERSISTENT_HEALTH_OK) do
      with_react_email_config(render_mode: :persistent) do
        assert(ReactEmailRails.healthy?)
      end
    end
  end

  test("healthy? returns false when the command fails") do
    with_react_email_internals(render_command: [RUBY, "-e", "exit 1"]) do
      assert_not(ReactEmailRails.healthy?)
    end
  end

  test("healthy? returns false when the renderer protocol is incompatible") do
    command = [
      RUBY,
      "-e",
      'require "json"; $stdout.write(JSON.generate(ok: true, protocolVersion: 0, packageVersion: "0.0.0")) if ARGV.include?("--health")',
      "--",
    ]

    with_react_email_internals(render_command: command) do
      assert_not(ReactEmailRails.healthy?)
    end
  end

  test("healthy? returns false when the command times out") do
    with_react_email_internals(render_command: [RUBY, "-e", "sleep 5"]) do
      with_react_email_config(render_timeout: 0.1) do
        assert_not(ReactEmailRails.healthy?)
      end
    end
  end
end
