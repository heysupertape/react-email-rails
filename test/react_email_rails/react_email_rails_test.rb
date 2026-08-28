require("json")
require("test_helper")

class ReactEmailRailsTest < ActiveSupport::TestCase
  RENDER_FIXED = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      while $stdin.gets
        $stdout.puts(JSON.generate(ok: true, html: "<p>Hi</p>", text: "Hi", #{RENDER_METADATA}))
        $stdout.flush
      end
    RUBY
    "--",
  ].freeze

  INCOMPATIBLE_HEALTH = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      $stdin.gets
      $stdout.puts(JSON.generate(ok: true, protocolVersion: 0, packageVersion: "0.0.0"))
      $stdout.flush
    RUBY
    "--",
  ].freeze

  teardown { ReactEmailRails::Renderer.stop_all }

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

  test("render serializes props without transforming keys by default") do
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
          "account_name" => "Ada",
          "nested_props" => { "owner_email" => "ada@example.com", "tags" => [{ "created_at" => "today" }] },
        },
      },
      JSON.parse(rendered.html),
    )
  end

  test("render applies prop_transformer before sending props") do
    rendered = with_react_email_internals(render_command: ECHO_INPUT) do
      with_react_email_config(
        prop_transformer: lambda { |props:|
          props.deep_transform_keys { |key| key.to_s.camelize(:lower) }
        },
      ) do
        ReactEmailRails.render(
          component: "users/welcome",
          props: { account_name: "Ada", nested_props: { owner_email: "ada@example.com", tags: [{ created_at: "today" }] } },
        )
      end
    end

    assert_equal(
      { "accountName" => "Ada", "nestedProps" => { "ownerEmail" => "ada@example.com", "tags" => [{ "createdAt" => "today" }] } },
      JSON.parse(rendered.html).fetch("props"),
    )
  end

  test("render invokes on_render_error with a uniform context and re-raises on failure") do
    reported = []

    with_react_email_internals(render_command: [RUBY, "-e", "exit 1", "--"]) do
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

  test("healthy? returns false when the command fails") do
    with_react_email_internals(render_command: [RUBY, "-e", "exit 1", "--"]) do
      assert_not(ReactEmailRails.healthy?)
    end
  end

  test("healthy? returns false when the renderer protocol is incompatible") do
    with_react_email_internals(render_command: INCOMPATIBLE_HEALTH) do
      assert_not(ReactEmailRails.healthy?)
    end
  end

  test("healthy? returns false when the command times out") do
    with_react_email_internals(render_command: [RUBY, "-e", "sleep 5", "--"]) do
      with_react_email_config(render_timeout: 0.1) do
        assert_not(ReactEmailRails.healthy?)
      end
    end
  end
end
