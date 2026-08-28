class ReactEmailRails::Configuration
  BUNDLE_PATH = "tmp/react-email-rails/emails.js"
  BUILD_BIN = "node_modules/.bin/react-email-rails-build"
  CONFIG_BIN = "node_modules/.bin/react-email-rails-config"
  DEV_RENDER_BIN = "node_modules/.bin/react-email-rails-dev"

  DEFAULT_RENDER_TIMEOUT = 10
  DEVELOPMENT_RENDER_TIMEOUT = 30
  DEFAULT_RENDER_PROCESS_MAX_REQUESTS = 1_000
  DEFAULT_LIVE_RELOAD_URL = "http://localhost:5173"

  DEFAULT_PROP_TRANSFORMER = ->(props:) { props }

  DEFAULT_RENDER_COMMAND = lambda do
    if Rails.env.development?
      [Rails.root.join(DEV_RENDER_BIN).to_s]
    else
      ["node", Rails.root.join(BUNDLE_PATH).to_s]
    end
  end

  attr_accessor(
    :component_path_resolver,
    :render_options,
    :on_render_error,
    :deep_merge_shared_props,
    :live_reload_url,
  )

  attr_reader(
    :prop_transformer,
    :render_timeout,
    :render_process_max_requests,
  )

  class << self
    def default
      new.tap do |config|
        config.component_path_resolver = ->(mailer:, action:) { "#{mailer}/#{action}" }
        config.render_options = {}
        config.render_timeout = Rails.env.development? ? DEVELOPMENT_RENDER_TIMEOUT : DEFAULT_RENDER_TIMEOUT
        config.render_process_max_requests = DEFAULT_RENDER_PROCESS_MAX_REQUESTS
        config.prop_transformer = DEFAULT_PROP_TRANSFORMER
        config.on_render_error = nil
        config.deep_merge_shared_props = false
        config.live_reload_url = DEFAULT_LIVE_RELOAD_URL
      end
    end
  end

  def resolve_live_reload_url
    return if live_reload_url.blank?

    live_reload_url.to_s.chomp("/")
  end

  def prop_transformer=(value)
    unless value.respond_to?(:call)
      raise(ArgumentError, "react-email-rails prop_transformer must be callable")
    end

    @prop_transformer = value
  end

  def render_timeout=(value)
    raise(ArgumentError, "react-email-rails render_timeout must be positive") unless value.is_a?(Numeric) && value.positive?

    @render_timeout = value
  end

  def render_process_max_requests=(value)
    unless value.nil? || (value.is_a?(Integer) && value.positive?)
      raise(ArgumentError, "react-email-rails render_process_max_requests must be a positive integer or nil")
    end

    @render_process_max_requests = value
  end

  def resolve_render_options(context = nil)
    value =
      if render_options.respond_to?(:call) && context
        context.instance_exec(&render_options)
      elsif render_options.respond_to?(:call)
        render_options.call
      else
        render_options
      end

    camelize_render_option_keys(value.as_json)
  end

  private

  def resolved_render_command
    DEFAULT_RENDER_COMMAND.call
  end

  def serialize_props(props)
    transform_serialized_props(props.as_json)
  end

  def transform_serialized_props(value)
    case value
    when Hash
      prop_transformer.call(props: value)
    when Array
      value.map { |item| transform_serialized_props(item) }
    else
      value
    end
  end

  def camelize_render_option_keys(value)
    case value
    when Hash
      value.deep_transform_keys { |key| key.to_s.camelize(:lower) }
    when Array
      value.map { |item| camelize_render_option_keys(item) }
    else
      value
    end
  end
end
