require("test_helper")

class ReactEmailRails::RenderModes::SubprocessTest < ActiveSupport::TestCase
  RUBY = RbConfig.ruby

  ECHO_INPUT = [
    RUBY,
    "-e",
    'require "json"; $stdout.write(JSON.generate(html: $stdin.read, text: ""))',
  ].freeze

  RENDER_FIXED = [
    RUBY,
    "-e",
    'require "json"; $stdin.read; $stdout.write(JSON.generate(html: "<p>Hello</p>", text: "Hello"))',
  ].freeze

  RENDER_PERSISTENT = [
    RUBY,
    "-e",
    <<~'RUBY',
      require "json"
      abort "missing persistent flag" unless ARGV.include?("--persistent")
      while (line = $stdin.gets)
        request = JSON.parse(line)
        name = request.fetch("props").fetch("name")
        $stdout.puts(JSON.generate(ok: true, html: "<p>Hello #{name}</p>", text: "Hello #{name}"))
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
      $stdout.puts(JSON.generate(ok: true, html: "x" * (1024 * 1024), text: ""))
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
        $stdout.puts(JSON.generate(ok: true, html: "<p>Hello</p>", text: Process.pid.to_s))
        $stdout.flush
      end
    RUBY
    "--",
  ].freeze

  RENDER_COUNTING = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      path = ARGV.fetch(0)
      count = File.exist?(path) ? File.read(path).to_i : 0
      File.write(path, count + 1)
      $stdin.read
      $stdout.write(JSON.generate(html: "<p>x</p>", text: ""))
    RUBY
    "--",
  ].freeze

  setup do
    Rails.cache.clear
  end

  teardown do
    Rails.cache.clear
    ReactEmailRails::RenderModes::Persistent::CommandRunner.stop_all
  end

  test("pipes the payload to the command and returns the rendered email") do
    rendered = with_react_email_config(render_command: RENDER_FIXED, cache_version: nil) do
      ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: { account_name: "Ada" }).render
    end

    assert_equal("<p>Hello</p>", rendered.html)
    assert_equal("Hello", rendered.text)
  end

  test("sends component and transformed props as the payload") do
    rendered = with_react_email_config(render_command: ECHO_INPUT, cache_version: nil) do
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

  test("can replace the default prop transformer") do
    rendered = with_react_email_config(
      render_command: ECHO_INPUT,
      cache_version: nil,
      prop_transformer: ->(props:) { props },
    ) do
      ReactEmailRails::RenderModes::Subprocess.new(
        component: "users/welcome",
        props: { account_name: "Ada", nested_props: { owner_email: "ada@example.com" } },
      ).render
    end

    assert_equal(
      { "account_name" => "Ada", "nested_props" => { "owner_email" => "ada@example.com" } },
      JSON.parse(rendered.html).fetch("props"),
    )
  end

  test("caches a render when cache options are given") do
    assert_capture_calls(1) do
      with_react_email_config(cache_version: nil) do
        2.times do
          ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: { name: "Ada" }, cache: true).render
        end
      end
    end
  end

  test("does not cache when cache is falsy") do
    assert_capture_calls(2) do
      with_react_email_config(cache_version: nil) do
        2.times do
          ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: { name: "Ada" }, cache: false).render
        end
      end
    end
  end

  test("busts the cache when cache_version changes") do
    assert_capture_calls(2) do
      with_react_email_config(cache_version: "v1") do
        ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: { name: "Ada" }, cache: true).render
      end

      with_react_email_config(cache_version: "v2") do
        ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: { name: "Ada" }, cache: true).render
      end
    end
  end

  test("raises render error with render process stderr on non-zero exit") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_config(render_command: [RUBY, "-e", '$stderr.write("component exploded"); exit 1']) do
        ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: {}).render
      end
    end

    assert_includes(error.message, "component exploded")
    assert_includes(error.message, "users/welcome")
  end

  test("raises render error when the render process returns invalid JSON") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_config(render_command: [RUBY, "-e", '$stdout.write("not json")']) do
        ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: {}).render
      end
    end

    assert_includes(error.message, "invalid JSON")
  end

  test("raises actionable render error when the command is missing") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_config(render_command: ["react-email-renderer-does-not-exist"]) do
        ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: {}).render
      end
    end

    assert_includes(error.message, "command not found")
  end

  test("kills and raises when the render process exceeds the timeout") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_config(render_command: [RUBY, "-e", "sleep 5"], render_timeout: 0.2) do
        ReactEmailRails::RenderModes::Subprocess.new(component: "users/welcome", props: {}).render
      end
    end

    assert_includes(error.message, "timed out")
  end

  test("persistent render mode keeps one command alive across renders") do
    rendered = with_react_email_config(render_command: RENDER_PERSISTENT, render_mode: :persistent) do
      [
        ReactEmailRails.render(component: "users/welcome", props: { name: "Ada" }),
        ReactEmailRails.render(component: "users/welcome", props: { name: "Grace" }),
      ]
    end

    assert_equal("<p>Hello Ada</p>", rendered.first.html)
    assert_equal("Hello Grace", rendered.second.text)
  end

  test("persistent render mode raises render process errors") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_config(render_command: RENDER_PERSISTENT_FAILURE, render_mode: :persistent) do
        ReactEmailRails.render(component: "users/welcome", props: {})
      end
    end

    assert_includes(error.message, "component exploded")
  end

  test("persistent render mode times out when a response line is incomplete") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_config(
        render_command: RENDER_PERSISTENT_PARTIAL_RESPONSE,
        render_mode: :persistent,
        render_timeout: 0.2,
      ) do
        ReactEmailRails.render(component: "users/welcome", props: {})
      end
    end

    assert_includes(error.message, "timed out")
  end

  test("persistent render mode reads large response lines without timing out") do
    rendered = with_react_email_config(
      render_command: RENDER_PERSISTENT_LARGE_RESPONSE,
      render_mode: :persistent,
      render_timeout: 1,
    ) do
      ReactEmailRails.render(component: "users/welcome", props: {})
    end

    assert_equal(1024 * 1024, rendered.html.bytesize)
  end

  test("persistent render processes are not shared across forks") do
    skip("fork is unavailable on this platform") unless Process.respond_to?(:fork)

    with_react_email_config(render_command: RENDER_PERSISTENT_PID, render_mode: :persistent) do
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

  test("persistent render mode recycles after the configured request count") do
    rendered = with_react_email_config(
      render_command: RENDER_PERSISTENT_PID,
      render_process_max_requests: 1,
      render_mode: :persistent,
    ) do
      [
        ReactEmailRails.render(component: "users/welcome", props: {}),
        ReactEmailRails.render(component: "users/welcome", props: {}),
      ]
    end

    assert_not_equal(rendered.first.text, rendered.second.text)
  end

  private

  def assert_capture_calls(expected_calls, &block)
    Dir.mktmpdir do |dir|
      counter_path = File.join(dir, "captures")

      with_react_email_config(render_command: [*RENDER_COUNTING, counter_path]) do
        block.yield
      end

      assert_equal(expected_calls, File.read(counter_path).to_i)
    end
  end
end
