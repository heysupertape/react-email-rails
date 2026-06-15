require("test_helper")

class ReactEmailRails::ConfigurationTest < ActiveSupport::TestCase
  test("defaults render mode to subprocess") do
    config = ReactEmailRails::Configuration.default

    assert_equal(:subprocess, config.render_mode)
    assert_equal(ReactEmailRails::RenderModes::Subprocess, config.resolved_render_mode)
  end

  test("defaults prop key transformation to lower camel case") do
    assert_equal(:lower_camel, ReactEmailRails::Configuration.default.transform_props)
  end

  test("resolves the persistent render mode shortcut") do
    config = ReactEmailRails::Configuration.default
    config.render_mode = :persistent

    assert_equal(ReactEmailRails::RenderModes::Persistent, config.resolved_render_mode)
  end

  test("rejects unknown render mode shortcuts") do
    config = ReactEmailRails::Configuration.default

    error = assert_raises(ArgumentError) { config.render_mode = :unknown }

    assert_equal("Unknown react-email-rails render mode: :unknown", error.message)
  end

  test("default prop serialization lower camelizes keys") do
    config = ReactEmailRails::Configuration.default

    props = config.send(:serialize_props, account_name: "Ada")

    assert_equal({ "accountName" => "Ada" }, props)
  end

  test("supports configured prop key transforms") do
    config = ReactEmailRails::Configuration.default
    input = { account_name: "Ada", nested_props: { owner_email: "ada@example.com" } }
    expected = {
      camel: { "AccountName" => "Ada", "NestedProps" => { "OwnerEmail" => "ada@example.com" } },
      lower_camel: { "accountName" => "Ada", "nestedProps" => { "ownerEmail" => "ada@example.com" } },
      dash: { "account-name" => "Ada", "nested-props" => { "owner-email" => "ada@example.com" } },
      snake: { "account_name" => "Ada", "nested_props" => { "owner_email" => "ada@example.com" } },
      none: { "account_name" => "Ada", "nested_props" => { "owner_email" => "ada@example.com" } },
    }

    expected.each do |transform, output|
      config.transform_props = transform
      assert_equal(output, config.send(:serialize_props, input))
    end
  end

  test("rejects unknown prop key transforms") do
    config = ReactEmailRails::Configuration.default
    config.transform_props = :unknown

    error = assert_raises(ArgumentError) { config.send(:serialize_props, account_name: "Ada") }

    assert_equal("Unknown react-email-rails prop transform: :unknown", error.message)
  end

  test("does not expose renderer internals as public configuration writers") do
    config = ReactEmailRails::Configuration.default

    assert_not_respond_to(config, :cache_store=)
    assert_not_respond_to(config, :cache_version=)
    assert_not_respond_to(config, :prop_serializer=)
    assert_not_respond_to(config, :render_command=)
  end

  test("defaults persistent render process recycling to a bounded request count") do
    assert_equal(1_000, ReactEmailRails::Configuration.default.render_process_max_requests)
  end

  test("rejects invalid render timeout values") do
    config = ReactEmailRails::Configuration.default

    assert_raises(ArgumentError) { config.render_timeout = 0 }
    assert_raises(ArgumentError) { config.render_timeout = "10" }
  end

  test("allows disabling or tuning persistent render process recycling") do
    config = ReactEmailRails::Configuration.default

    config.render_process_max_requests = nil
    assert_nil(config.render_process_max_requests)

    config.render_process_max_requests = 50
    assert_equal(50, config.render_process_max_requests)

    assert_raises(ArgumentError) { config.render_process_max_requests = 0 }
  end

  test("render options default to an empty hash") do
    assert_equal({}, ReactEmailRails::Configuration.default.resolve_render_options)
  end

  test("render options are camelized for the JavaScript renderer") do
    config = ReactEmailRails::Configuration.default
    config.render_options = {
      html: { pretty: true },
      text: { html_to_text_options: { wordwrap: false } },
    }

    assert_equal(
      {
        "html" => { "pretty" => true },
        "text" => { "htmlToTextOptions" => { "wordwrap" => false } },
      },
      config.resolve_render_options,
    )
  end

  test("render options can be evaluated in a mailer context") do
    config = ReactEmailRails::Configuration.default
    config.render_options = -> { { html: { pretty: pretty_email? } } }
    context = Object.new
    def context.pretty_email? = true

    assert_equal({ "html" => { "pretty" => true } }, config.resolve_render_options(context))
  end

  test("live reload url defaults to the vite dev server and strips a trailing slash") do
    config = ReactEmailRails::Configuration.default

    assert_equal("http://localhost:5173", config.resolve_live_reload_url)

    config.live_reload_url = "http://localhost:6006/"
    assert_equal("http://localhost:6006", config.resolve_live_reload_url)
  end

  test("a falsy live reload url disables live reload") do
    config = ReactEmailRails::Configuration.default

    [nil, false, ""].each do |value|
      config.live_reload_url = value
      assert_nil(config.resolve_live_reload_url, "expected #{value.inspect} to disable live reload")
    end
  end
end
