require("test_helper")

class ReactEmailRails::RendererTest < ActiveSupport::TestCase
  RENDER_FIXED = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      while $stdin.gets
        $stdout.puts(JSON.generate(ok: true, html: "<p>Hello</p>", text: "Hello", #{RENDER_METADATA}))
        $stdout.flush
      end
    RUBY
    "--",
  ].freeze

  RENDER_PROPS = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      while (line = $stdin.gets)
        request = JSON.parse(line)
        name = request.fetch("props").fetch("name")
        $stdout.puts(JSON.generate(ok: true, html: "<p>Hello \#{name}</p>", text: "Hello \#{name}", #{RENDER_METADATA}))
        $stdout.flush
      end
    RUBY
    "--",
  ].freeze

  RENDER_FAILURE = [
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

  RENDER_PARTIAL_RESPONSE = [
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

  RENDER_LARGE_RESPONSE = [
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

  RENDER_PID = [
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

  RENDER_CRASH_WITH_STDERR = [
    RUBY,
    "-e",
    <<~RUBY,
      $stdin.gets
      $stderr.write("component exploded")
      exit 1
    RUBY
    "--",
  ].freeze

  RENDER_INVALID_JSON = [
    RUBY,
    "-e",
    <<~RUBY,
      $stdin.gets
      $stdout.puts("not json")
      $stdout.flush
    RUBY
    "--",
  ].freeze

  RENDER_PROTOCOL_MISMATCH = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      $stdin.gets
      $stdout.puts(JSON.generate(ok: true, html: "<p>Hello</p>", text: "Hello", protocolVersion: 0, packageVersion: "0.0.0"))
      $stdout.flush
    RUBY
    "--",
  ].freeze

  RENDER_MISSING_HTML = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      $stdin.gets
      $stdout.puts(JSON.generate(ok: true, text: "Hello", #{RENDER_METADATA}))
      $stdout.flush
    RUBY
    "--",
  ].freeze

  teardown do
    ReactEmailRails::Renderer.stop_all
  end

  def renderer(component:, props: {})
    ReactEmailRails::Renderer.new(
      payload: { component:, props: },
      label: component,
    )
  end

  test("pipes the payload to the command and returns the rendered email") do
    rendered = with_react_email_internals(render_command: RENDER_FIXED) do
      renderer(component: "users/welcome", props: { account_name: "Ada" }).render
    end

    assert_equal("<p>Hello</p>", rendered.html)
    assert_equal("Hello", rendered.text)
  end

  test("ships the constructed payload to the command verbatim") do
    rendered = with_react_email_internals(render_command: ECHO_INPUT) do
      ReactEmailRails::Renderer.new(
        payload: { component: "users/welcome", props: { "accountName" => "Ada" } },
        label: "users/welcome",
      ).render
    end

    assert_equal(
      { "component" => "users/welcome", "props" => { "accountName" => "Ada" } },
      JSON.parse(rendered.html),
    )
  end

  test("raises render error with render process stderr on failure") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: RENDER_CRASH_WITH_STDERR) do
        renderer(component: "users/welcome").render
      end
    end

    assert_includes(error.message, "component exploded")
    assert_includes(error.message, "users/welcome")
  end

  test("raises render error when the render process returns invalid JSON") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: RENDER_INVALID_JSON) do
        renderer(component: "users/welcome").render
      end
    end

    assert_includes(error.message, "invalid JSON")
  end

  test("recycles the child after invalid JSON so the next render can succeed") do
    Dir.mktmpdir do |dir|
      marker = File.join(dir, "used")
      command = [
        RUBY,
        "-e",
        <<~RUBY,
          require "json"
          marker = #{marker.inspect}
          $stdin.gets
          if File.exist?(marker)
            $stdout.puts(JSON.generate(ok: true, html: "<p>Hello</p>", text: "Hello", #{RENDER_METADATA}))
            $stdout.flush
          else
            File.write(marker, "1")
            $stdout.puts("not json")
            $stdout.flush
          end
        RUBY
        "--",
      ]

      rendered = with_react_email_internals(render_command: command) do
        error = assert_raises(ReactEmailRails::RenderError) do
          renderer(component: "users/welcome").render
        end
        assert_includes(error.message, "invalid JSON")
        renderer(component: "users/welcome").render
      end
      assert_equal("<p>Hello</p>", rendered.html)
    end
  end

  test("raises render error when the renderer protocol is incompatible") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: RENDER_PROTOCOL_MISMATCH) do
        renderer(component: "users/welcome").render
      end
    end

    assert_includes(error.message, "renderer version mismatch")
  end

  test("raises render error when the renderer omits html") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: RENDER_MISSING_HTML) do
        renderer(component: "users/welcome").render
      end
    end

    assert_includes(error.message, "missing \"html\"")
  end

  test("raises actionable render error when the default production bundle is missing") do
    missing_bundle = File.join(Dir.tmpdir, "react-email-rails-missing", ReactEmailRails::Configuration::BUNDLE_PATH)

    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: ["node", missing_bundle]) do
        renderer(component: "users/welcome").render
      end
    end

    assert_includes(error.message, "email bundle not found")
    assert_includes(error.message, "react-email-rails-build")
  end

  test("raises actionable render error when the command is missing") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: ["react-email-renderer-does-not-exist"]) do
        renderer(component: "users/welcome").render
      end
    end

    assert_includes(error.message, "command not found")
  end

  test("kills and raises when the render process exceeds the timeout") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: [RUBY, "-e", "sleep 5", "--"]) do
        with_react_email_config(render_timeout: 0.2) do
          renderer(component: "users/welcome").render
        end
      end
    end

    assert_includes(error.message, "timed out")
    assert_includes(error.message, "react-email-rails must both be #{ReactEmailRails::VERSION}")
  end

  test("keeps one command alive across renders") do
    rendered = with_react_email_internals(render_command: RENDER_PROPS) do
      [
        ReactEmailRails.render(component: "users/welcome", props: { name: "Ada" }),
        ReactEmailRails.render(component: "users/welcome", props: { name: "Grace" }),
      ]
    end

    assert_equal("<p>Hello Ada</p>", rendered.first.html)
    assert_equal("Hello Grace", rendered.second.text)
  end

  test("raises render process errors") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: RENDER_FAILURE) do
        ReactEmailRails.render(component: "users/welcome", props: {})
      end
    end

    assert_includes(error.message, "component exploded")
  end

  test("times out when a response line is incomplete") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_internals(render_command: RENDER_PARTIAL_RESPONSE) do
        with_react_email_config(render_timeout: 0.2) do
          ReactEmailRails.render(component: "users/welcome", props: {})
        end
      end
    end

    assert_includes(error.message, "timed out")
    assert_not_includes(error.message, "must both be")
  end

  test("reads large response lines without timing out") do
    rendered = with_react_email_internals(render_command: RENDER_LARGE_RESPONSE) do
      with_react_email_config(render_timeout: 1) do
        ReactEmailRails.render(component: "users/welcome", props: {})
      end
    end

    assert_equal(1024 * 1024, rendered.html.bytesize)
  end

  test("render processes are not shared across forks") do
    skip("fork is unavailable on this platform") unless Process.respond_to?(:fork)

    with_react_email_internals(render_command: RENDER_PID) do
      parent_render_pid = ReactEmailRails.render(component: "users/welcome", props: {}).text

      reader, writer = IO.pipe
      child = fork do
        reader.close
        child_render_pid = ReactEmailRails.render(component: "users/welcome", props: {}).text
        writer.write(child_render_pid)
        writer.close
        ReactEmailRails::Renderer.stop_all
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

  test("recycles after the configured request count") do
    rendered = with_react_email_internals(render_command: RENDER_PID) do
      with_react_email_config(render_process_max_requests: 1) do
        [
          ReactEmailRails.render(component: "users/welcome", props: {}),
          ReactEmailRails.render(component: "users/welcome", props: {}),
        ]
      end
    end

    assert_not_equal(rendered.first.text, rendered.second.text)
  end
end
