require("test_helper")

class ReactEmailRails::RenderModes::SubprocessTest < ActiveSupport::TestCase
  RUBY = RbConfig.ruby
  RENDER_METADATA = "protocolVersion: #{ReactEmailRails::RENDER_PROTOCOL_VERSION}, packageVersion: #{ReactEmailRails::VERSION.inspect}"

  ECHO_INPUT = [
    RUBY,
    "-e",
    "require \"json\"; $stdout.write(JSON.generate(html: $stdin.read, text: \"\", #{RENDER_METADATA}))",
  ].freeze

  RENDER_FIXED = [
    RUBY,
    "-e",
    "require \"json\"; $stdin.read; $stdout.write(JSON.generate(html: \"<p>Hello</p>\", text: \"Hello\", #{RENDER_METADATA}))",
  ].freeze

  RENDER_PERSISTENT = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      abort "missing persistent flag" unless ARGV.include?("--persistent")
      while (line = $stdin.gets)
        request = JSON.parse(line)
        name = request.fetch("props").fetch("name")
        $stdout.puts(JSON.generate(ok: true, html: "<p>Hello \#{name}</p>", text: "Hello \#{name}", #{RENDER_METADATA}))
        $stdout.flush
      end
    RUBY
    "--",
  ].freeze

  RENDER_PERSISTENT_FAILURE = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      while $stdin.gets
        $stdout.puts(JSON.generate(ok: false, error: "component exploded"))
        $stdout.flush
      end
    RUBY
    "--",
  ].freeze

  RENDER_PERSISTENT_PARTIAL_RESPONSE = [
    RUBY,
    "-e",
    <<~RUBY,
      $stdin.gets
      $stdout.write("{")
      $stdout.flush
      sleep 5
    RUBY
    "--",
  ].freeze

  RENDER_PERSISTENT_LARGE_RESPONSE = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      $stdin.gets
      $stdout.puts(JSON.generate(ok: true, html: "x" * (1024 * 1024), text: "", #{RENDER_METADATA}))
      $stdout.flush
    RUBY
    "--",
  ].freeze

  RENDER_PERSISTENT_PID = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      while $stdin.gets
        $stdout.puts(JSON.generate(ok: true, html: "<p>Hello</p>", text: Process.pid.to_s, #{RENDER_METADATA}))
        $stdout.flush
      end
    RUBY
    "--",
  ].freeze

  teardown do
    ReactEmailRails::RenderModes::Persistent::CommandRunner.stop_all
  end

  test("pipes the payload to the command and returns the rendered email") do
    rendered = with_react_email_internals(render_command: RENDER_FIXED) do
      ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: { account_name: "Ada" }).render
    end

    assert_equal("<p>Hello</p>", rendered.html)
    assert_equal("Hello", rendered.text)
  end

  test("sends component and transformed props as the payload") do
    rendered = with_react_email_internals(render_command: ECHO_INPUT) do
      ReactEmailRails::RenderModes::Subprocess.new(
        component: "users/welcome",
        props: {
          account_name: "Ada",
          nested_props: { owner_email: "ada@example.com", tags: [{ created_at: "today" }] },
        },
      ).render
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

  test("can send serialized props without camelizing keys") do
    rendered = with_react_email_internals(render_command: ECHO_INPUT) do
      with_react_email_config(transform_props: :none) do
        ReactEmailRails::RenderModes::Subprocess.new(
          component: "users/welcome",
          props: { account_name: "Ada", nested_props: { owner_email: "ada@example.com" } },
        ).render
      end
    end

    assert_equal(
      { "account_name" => "Ada", "nested_props" => { "owner_email" => "ada@example.com" } },
      JSON.parse(rendered.html).fetch("props"),
    )
  end

  test("raises render error with render process stderr on non-zero exit") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: [RUBY, "-e", '$stderr.write("component exploded"); exit 1']) do
        ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: {}).render
      end
    end

    assert_includes(error.message, "component exploded")
    assert_includes(error.message, "users/welcome")
  end

  test("raises render error when the render process returns invalid JSON") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: [RUBY, "-e", '$stdout.write("not json")']) do
        ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: {}).render
      end
    end

    assert_includes(error.message, "invalid JSON")
  end

  test("raises render error when the renderer protocol is incompatible") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(
        render_command: [RUBY, "-e", 'require "json"; $stdout.write(JSON.generate(html: "<p>Hello</p>", text: "Hello", protocolVersion: 0, packageVersion: "0.0.0"))'],
      ) do
        ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: {}).render
      end
    end

    assert_includes(error.message, "renderer version mismatch")
  end

  test("raises render error when the renderer omits html") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(
        render_command: [RUBY, "-e", "require \"json\"; $stdout.write(JSON.generate(text: \"Hello\", #{RENDER_METADATA}))"],
      ) do
        ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: {}).render
      end
    end

    assert_includes(error.message, "missing \"html\"")
  end

  test("raises actionable render error when the default production bundle is missing") do
    missing_bundle = File.join(Dir.tmpdir, "react-email-rails-missing", ReactEmailRails::Configuration::BUNDLE_PATH)

    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: ["node", missing_bundle]) do
        ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: {}).render
      end
    end

    assert_includes(error.message, "email bundle not found")
    assert_includes(error.message, "vite build")
  end

  test("raises actionable render error when the command is missing") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: ["react-email-renderer-does-not-exist"]) do
        ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: {}).render
      end
    end

    assert_includes(error.message, "command not found")
  end

  test("kills and raises when the render process exceeds the timeout") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: [RUBY, "-e", "sleep 5"]) do
        with_react_email_config(render_timeout: 0.2) do
          ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: {}).render
        end
      end
    end

    assert_includes(error.message, "timed out")
  end

  test("persistent render mode keeps one command alive across renders") do
    rendered = with_react_email_internals(render_command: RENDER_PERSISTENT) do
      with_react_email_config(render_mode: :persistent) do
        [
          ReactEmailRails.render(component: "users/welcome", props: { name: "Ada" }),
          ReactEmailRails.render(component: "users/welcome", props: { name: "Grace" }),
        ]
      end
    end

    assert_equal("<p>Hello Ada</p>", rendered.first.html)
    assert_equal("Hello Grace", rendered.second.text)
  end

  test("persistent render mode raises render process errors") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: RENDER_PERSISTENT_FAILURE) do
        with_react_email_config(render_mode: :persistent) do
          ReactEmailRails.render(component: "users/welcome", props: {})
        end
      end
    end

    assert_includes(error.message, "component exploded")
  end

  test("persistent render mode times out when a response line is incomplete") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: RENDER_PERSISTENT_PARTIAL_RESPONSE) do
        with_react_email_config(render_mode: :persistent, render_timeout: 0.2) do
          ReactEmailRails.render(component: "users/welcome", props: {})
        end
      end
    end

    assert_includes(error.message, "timed out")
  end

  test("persistent render mode reads large response lines without timing out") do
    rendered = with_react_email_internals(render_command: RENDER_PERSISTENT_LARGE_RESPONSE) do
      with_react_email_config(render_mode: :persistent, render_timeout: 1) do
        ReactEmailRails.render(component: "users/welcome", props: {})
      end
    end

    assert_equal(1024 * 1024, rendered.html.bytesize)
  end

  test("persistent render processes are not shared across forks") do
    skip("fork is unavailable on this platform") unless Process.respond_to?(:fork)

    with_react_email_internals(render_command: RENDER_PERSISTENT_PID) do
      with_react_email_config(render_mode: :persistent) do
        parent_render_pid = ReactEmailRails.render(component: "users/welcome", props: {}).text

        reader, writer = IO.pipe
        child = fork do
          reader.close
          child_render_pid = ReactEmailRails.render(component: "users/welcome", props: {}).text
          writer.write(child_render_pid)
          writer.close
          ReactEmailRails::RenderModes::Persistent::CommandRunner.stop_all
          exit!(0)
        end
        writer.close
        child_render_pid = reader.read
        reader.close
        Process.wait(child)

        assert_not_equal("", child_render_pid)
        assert_not_equal(parent_render_pid, child_render_pid)
      end
    end
  end

  test("persistent render mode recycles after the configured request count") do
    rendered = with_react_email_internals(render_command: RENDER_PERSISTENT_PID) do
      with_react_email_config(render_mode: :persistent, render_process_max_requests: 1) do
        [
          ReactEmailRails.render(component: "users/welcome", props: {}),
          ReactEmailRails.render(component: "users/welcome", props: {}),
        ]
      end
    end

    assert_not_equal(rendered.first.text, rendered.second.text)
  end
end
