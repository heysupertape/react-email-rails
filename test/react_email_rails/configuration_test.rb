require("test_helper")

class ReactEmailRails::ConfigurationTest < ActiveSupport::TestCase
  test("defaults render timeout outside development") do
    config = ReactEmailRails::Configuration.default

    assert_equal(ReactEmailRails::Configuration::DEFAULT_RENDER_TIMEOUT, config.render_timeout)
  end

  test("defaults a longer render timeout in development") do
    previous = Rails.env
    Rails.env = "development"
    config = ReactEmailRails::Configuration.default

    assert_equal(ReactEmailRails::Configuration::DEVELOPMENT_RENDER_TIMEOUT, config.render_timeout)
  ensure
    Rails.env = previous
  end

  test("leaves prop keys as serialized by default") do
    config = ReactEmailRails::Configuration.default

    assert_equal(
      { "account_name" => "Ada", "nested_props" => { "owner_email" => "ada@example.com" } },
      config.send(:serialize_props, account_name: "Ada", nested_props: { owner_email: "ada@example.com" }),
    )
  end

  test("applies a configured prop_transformer after as_json") do
    config = ReactEmailRails::Configuration.default
    config.prop_transformer = lambda do |props:|
      props.deep_transform_keys { |key| key.to_s.camelize(:lower) }
    end
    serializer = Object.new
    def serializer.as_json(*)
      { "account_name" => "Ada", "nested_props" => { "owner_email" => "ada@example.com" } }
    end

    assert_equal(
      { "accountName" => "Ada", "nestedProps" => { "ownerEmail" => "ada@example.com" } },
      config.send(:serialize_props, serializer),
    )
  end

  test("applies prop_transformer to hashes inside a top-level array") do
    config = ReactEmailRails::Configuration.default
    config.prop_transformer = lambda do |props:|
      props.deep_transform_keys { |key| key.to_s.camelize(:lower) }
    end

    assert_equal(
      [{ "createdAt" => "today" }, { "ownerEmail" => "ada@example.com" }],
      config.send(:serialize_props, [{ created_at: "today" }, { owner_email: "ada@example.com" }]),
    )
  end

  test("rejects a non-callable prop_transformer") do
    config = ReactEmailRails::Configuration.default

    error = assert_raises(ArgumentError) { config.prop_transformer = :lower_camel }

    assert_equal("react-email-rails prop_transformer must be callable", error.message)
  end

  test("does not expose renderer internals as public configuration writers") do
    config = ReactEmailRails::Configuration.default

    assert_not_respond_to(config, :cache_store=)
    assert_not_respond_to(config, :cache_version=)
    assert_not_respond_to(config, :prop_serializer=)
    assert_not_respond_to(config, :render_command=)
    assert_not_respond_to(config, :render_mode=)
    assert_not_respond_to(config, :renderer=)
    assert_not_respond_to(config, :transform_props=)
    assert_not_respond_to(config, :camelize_props=)
  end

  test("defaults render process recycling to a bounded request count") do
    assert_equal(1_000, ReactEmailRails::Configuration.default.render_process_max_requests)
  end

  test("rejects invalid render timeout values") do
    config = ReactEmailRails::Configuration.default

    assert_raises(ArgumentError) { config.render_timeout = 0 }
    assert_raises(ArgumentError) { config.render_timeout = "10" }
  end

  test("allows disabling or tuning render process recycling") do
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

  test("render options that are not a hash pass through without camelizing") do
    config = ReactEmailRails::Configuration.default

    config.render_options = nil
    assert_nil(config.resolve_render_options)

    config.render_options = -> { nil }
    assert_nil(config.resolve_render_options)
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
