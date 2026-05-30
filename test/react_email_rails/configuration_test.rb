require("test_helper")

class ReactEmailRails::ConfigurationTest < ActiveSupport::TestCase
  test("defaults cache to Action Mailer caching") do
    original = ActionMailer::Base.perform_caching
    ActionMailer::Base.perform_caching = !original

    assert_equal(!original, ReactEmailRails::Configuration.default.cache)
  ensure
    ActionMailer::Base.perform_caching = original
  end

  test("defaults render process recycling to a bounded request count") do
    assert_equal(1_000, ReactEmailRails::Configuration.default.render_process_max_requests)
  end

  test("defaults render mode to subprocess") do
    config = ReactEmailRails::Configuration.default

    assert_equal(:subprocess, config.render_mode)
    assert_equal(ReactEmailRails::RenderModes::Subprocess, config.resolved_render_mode)
  end

  test("resolves the persistent render mode shortcut") do
    config = ReactEmailRails::Configuration.default
    config.render_mode = :persistent

    assert_equal(ReactEmailRails::RenderModes::Persistent, config.resolved_render_mode)
  end

  test("rejects unknown render mode shortcuts") do
    config = ReactEmailRails::Configuration.default
    config.render_mode = :unknown

    error = assert_raises(ArgumentError) { config.resolved_render_mode }

    assert_equal("Unknown react-email-rails render mode: :unknown", error.message)
  end

  test("resolve_cache returns a static cache value") do
    config = ReactEmailRails::Configuration.default
    config.cache = { expires_in: 1 }

    assert_equal({ expires_in: 1 }, config.resolve_cache)
  end

  test("resolve_cache evaluates a callable in the given context") do
    config = ReactEmailRails::Configuration.default
    config.cache = -> { caching_for_action }
    context = Object.new
    def context.caching_for_action = { expires_in: 5 }

    assert_equal({ expires_in: 5 }, config.resolve_cache(context))
  end

  test("resolved_cache_version evaluates a callable") do
    config = ReactEmailRails::Configuration.default
    config.cache_version = -> { "v2" }

    assert_equal("v2", config.resolved_cache_version)
  end

  test("resolves a callable render command lazily") do
    config = ReactEmailRails::Configuration.default
    config.render_command = -> { ["node", "renderer.js"] }

    assert_equal(["node", "renderer.js"], config.resolved_render_command)
  end

  test("resolves a static render command") do
    config = ReactEmailRails::Configuration.default
    config.render_command = ["node", "renderer.js"]

    assert_equal(["node", "renderer.js"], config.resolved_render_command)
  end

  test("defaults cache store to Rails.cache") do
    assert_same(Rails.cache, ReactEmailRails::Configuration.default.cache_store)
  end

  test("falls back to Rails.cache when cache store is nil") do
    config = ReactEmailRails::Configuration.default
    config.cache_store = nil

    assert_same(Rails.cache, config.resolved_cache_store)
  end

  test("verify_render_on_boot? evaluates a callable option") do
    config = ReactEmailRails::Configuration.default
    config.verify_render_on_boot = -> { true }

    assert(config.verify_render_on_boot?)

    config.verify_render_on_boot = -> { false }
    assert_not(config.verify_render_on_boot?)
  end

  test("verify_render_on_boot? coerces a static option to a boolean") do
    config = ReactEmailRails::Configuration.default

    config.verify_render_on_boot = false
    assert_not(config.verify_render_on_boot?)

    config.verify_render_on_boot = "truthy"
    assert(config.verify_render_on_boot?)
  end

  test("default prop pipeline serializes and camelizes props") do
    config = ReactEmailRails::Configuration.default

    props = config.transform_props(account_name: "Ada")

    assert_equal({ "accountName" => "Ada" }, props)
  end

  test("custom prop serializer controls object serialization") do
    config = ReactEmailRails::Configuration.default
    config.prop_serializer = ->(props:) { props.merge(serialized_by: "custom") }

    props = config.transform_props(account_name: "Ada")

    assert_equal({ "accountName" => "Ada", "serializedBy" => "custom" }, props)
  end

  test("custom prop transformer controls the final prop shape") do
    config = ReactEmailRails::Configuration.default
    config.prop_transformer = ->(props:) { props.merge("fromTransformer" => true) }

    props = config.transform_props(account_name: "Ada")

    assert_equal({ "account_name" => "Ada", "fromTransformer" => true }, props)
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
end
