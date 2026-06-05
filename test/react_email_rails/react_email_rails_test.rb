require("json")
require("test_helper")

class ReactEmailRailsTest < ActiveSupport::TestCase
  RENDER_FIXED = [
    RUBY,
    "-e",
    "require \"json\"; $stdin.read; $stdout.write(JSON.generate(html: \"<p>Hi</p>\", text: \"Hi\", #{RENDER_METADATA}))",
  ].freeze

  COMPOSE_PERSISTENT = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      abort "missing persistent flag" unless ARGV.include?("--persistent")
      while (line = $stdin.gets)
        request = JSON.parse(line)
        $stdout.puts(JSON.generate(ok: true, html: "<p>\#{request["type"]}</p>", text: request["kind"], warnings: [{ type: "embed", count: 1 }], #{RENDER_METADATA}))
        $stdout.flush
      end
    RUBY
    "--",
  ].freeze

  COMPOSE_WITH_WARNINGS = [
    RUBY,
    "-e",
    "require \"json\"; $stdin.read; $stdout.write(JSON.generate(html: \"<p>Hi</p>\", text: \"Hi\", warnings: [{ type: \"customBlock\", count: 2 }], #{RENDER_METADATA}))",
  ].freeze

  PARSE_ECHO = [
    RUBY,
    "-e",
    "require \"json\"; $stdout.write(JSON.generate(document: JSON.parse($stdin.read), #{RENDER_METADATA}))",
  ].freeze

  PARSE_FIXED = [
    RUBY,
    "-e",
    "require \"json\"; $stdin.read; $stdout.write(JSON.generate(document: { type: \"doc\", content: [{ type: \"paragraph\" }] }, #{RENDER_METADATA}))",
  ].freeze

  PARSE_PERSISTENT = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      abort "missing persistent flag" unless ARGV.include?("--persistent")
      while (line = $stdin.gets)
        request = JSON.parse(line)
        $stdout.puts(JSON.generate(ok: true, document: { type: "doc", source: request["html"] }, #{RENDER_METADATA}))
        $stdout.flush
      end
    RUBY
    "--",
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
    assert_equal("email", payload[:kind])
    assert_equal("users/welcome", payload[:component])
    assert_equal("<p>Hi</p>".bytesize, payload[:html_bytes])
    assert_nil(payload[:warnings])
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

  test("compose sends a document payload with the document verbatim and the context camelized") do
    document = {
      "type" => "doc",
      "content" => [
        { "type" => "globalContent", "attrs" => {} },
        {
          "type" => "custom_block",
          "attrs" => { "image_url" => "https://example.com/logo.png" },
          "content" => [{ "type" => "text", "text" => "Hi" }],
        },
      ],
    }

    rendered = with_react_email_internals(render_command: ECHO_INPUT) do
      ReactEmailRails.compose(
        type: "broadcast",
        document:,
        context: { brand_name: "Acme", nested_thing: { logo_url: "https://example.com/logo.png" } },
        preview: "Inbox preview",
      )
    end

    payload = JSON.parse(rendered.html)
    assert_equal("document", payload.fetch("kind"))
    assert_equal("broadcast", payload.fetch("type"))
    assert_equal("Inbox preview", payload.fetch("preview"))
    # Structural document keys (custom_block, image_url) are untouched...
    assert_equal(document, payload.fetch("document"))
    # ...while context keys are camelized like component props.
    assert_equal(
      { "brandName" => "Acme", "nestedThing" => { "logoUrl" => "https://example.com/logo.png" } },
      payload.fetch("context"),
    )
  end

  test("compose returns the rendered html and text") do
    rendered = with_react_email_internals(render_command: RENDER_FIXED) do
      ReactEmailRails.compose(type: "broadcast", document: { "type" => "doc" })
    end

    assert_equal("<p>Hi</p>", rendered.html)
    assert_equal("Hi", rendered.text)
  end

  test("compose renders through the persistent render mode") do
    rendered = with_react_email_internals(render_command: COMPOSE_PERSISTENT) do
      with_react_email_config(render_mode: :persistent) do
        ReactEmailRails.compose(type: "broadcast", document: { "type" => "doc" })
      end
    end

    assert_equal("<p>broadcast</p>", rendered.html)
    assert_equal("document", rendered.text)
    assert_equal([{ type: "embed", count: 1 }], rendered.warnings)
  end

  test("compose surfaces dropped-node warnings on the result and in instrumentation") do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("render.react-email-rails") { |event| events << event }

    rendered = with_react_email_internals(render_command: COMPOSE_WITH_WARNINGS) do
      ReactEmailRails.compose(type: "broadcast", document: { "type" => "doc" })
    end

    assert_equal([{ type: "customBlock", count: 2 }], rendered.warnings)
    assert_equal([{ type: "customBlock", count: 2 }], events.sole.payload[:warnings])
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test("compose emits a render.react-email-rails notification with kind, type, and html size") do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("render.react-email-rails") { |event| events << event }

    with_react_email_internals(render_command: RENDER_FIXED) do
      ReactEmailRails.compose(type: "broadcast", document: { "type" => "doc" })
    end

    payload = events.sole.payload
    assert_equal("document", payload[:kind])
    assert_equal("broadcast", payload[:type])
    assert_equal("<p>Hi</p>".bytesize, payload[:html_bytes])
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test("compose invokes on_render_error with a uniform context and re-raises on failure") do
    reported = []

    with_react_email_internals(render_command: [RUBY, "-e", "exit 1"]) do
      with_react_email_config(on_render_error: ->(error, **context) { reported << [error, context] }) do
        assert_raises(ReactEmailRails::RenderError) do
          ReactEmailRails.compose(type: "broadcast", document: { "type" => "doc" })
        end
      end
    end

    error, context = reported.sole
    assert_instance_of(ReactEmailRails::RenderError, error)
    assert_equal({ kind: "document", type: "broadcast" }, context)
  end

  test("parse sends a parse payload with the html verbatim and the context camelized") do
    document = with_react_email_internals(render_command: PARSE_ECHO) do
      ReactEmailRails.parse(
        type: "broadcast",
        html: "<h1>Hello</h1>",
        context: { brand_name: "Acme", nested_thing: { logo_url: "https://example.com/logo.png" } },
      )
    end

    assert_equal("parse", document.fetch("kind"))
    assert_equal("broadcast", document.fetch("type"))
    assert_equal("<h1>Hello</h1>", document.fetch("html"))
    assert_nil(document["markdown"])
    assert_equal(
      { "brandName" => "Acme", "nestedThing" => { "logoUrl" => "https://example.com/logo.png" } },
      document.fetch("context"),
    )
  end

  test("parse sends a parse payload with the markdown verbatim and the context camelized") do
    document = with_react_email_internals(render_command: PARSE_ECHO) do
      ReactEmailRails.parse(
        type: "broadcast",
        markdown: "# Hello",
        context: { brand_name: "Acme" },
      )
    end

    assert_equal("parse", document.fetch("kind"))
    assert_equal("broadcast", document.fetch("type"))
    assert_equal("# Hello", document.fetch("markdown"))
    assert_nil(document["html"])
    assert_equal({ "brandName" => "Acme" }, document.fetch("context"))
  end

  test("parse raises when both html and markdown are given") do
    error = assert_raises(ArgumentError) do
      ReactEmailRails.parse(type: "broadcast", html: "<p>Hi</p>", markdown: "Hi")
    end

    assert_match(/only one of html: or markdown:/, error.message)
  end

  test("parse raises when neither html nor markdown is given") do
    error = assert_raises(ArgumentError) do
      ReactEmailRails.parse(type: "broadcast")
    end

    assert_match(/requires html: or markdown:/, error.message)
  end

  test("parse returns the parsed document") do
    document = with_react_email_internals(render_command: PARSE_FIXED) do
      ReactEmailRails.parse(type: "broadcast", html: "<p>Hi</p>")
    end

    assert_equal({ "type" => "doc", "content" => [{ "type" => "paragraph" }] }, document)
  end

  test("parse returns the document through the persistent render mode") do
    document = with_react_email_internals(render_command: PARSE_PERSISTENT) do
      with_react_email_config(render_mode: :persistent) do
        ReactEmailRails.parse(type: "broadcast", html: "<h1>Hi</h1>")
      end
    end

    assert_equal({ "type" => "doc", "source" => "<h1>Hi</h1>" }, document)
  end

  test("parse raises when the renderer response has no document") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: RENDER_FIXED) do
        ReactEmailRails.parse(type: "broadcast", html: "<p>Hi</p>")
      end
    end

    assert_match(/missing "document"/, error.message)
  end

  test("parse emits a render.react-email-rails notification with the parse kind and type") do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("render.react-email-rails") { |event| events << event }

    with_react_email_internals(render_command: PARSE_FIXED) do
      ReactEmailRails.parse(type: "broadcast", html: "<p>Hi</p>")
    end

    payload = events.sole.payload
    assert_equal("parse", payload[:kind])
    assert_equal("broadcast", payload[:type])
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test("parse invokes on_render_error with a uniform context and re-raises on failure") do
    reported = []

    with_react_email_internals(render_command: [RUBY, "-e", "exit 1"]) do
      with_react_email_config(on_render_error: ->(error, **context) { reported << [error, context] }) do
        assert_raises(ReactEmailRails::RenderError) do
          ReactEmailRails.parse(type: "broadcast", html: "<p>Hi</p>")
        end
      end
    end

    error, context = reported.sole
    assert_instance_of(ReactEmailRails::RenderError, error)
    assert_equal({ kind: "parse", type: "broadcast" }, context)
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
    assert_equal({ kind: "email", component: "users/welcome" }, context)
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
