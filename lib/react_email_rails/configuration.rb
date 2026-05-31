class ReactEmailRails::Configuration
  BUNDLE_PATH = "tmp/react-email-rails/emails.js"
  BUILD_BIN = "node_modules/.bin/react-email-rails-build"
  DEV_RENDER_BIN = "node_modules/.bin/react-email-rails-dev"

  DEFAULT_RENDER_TIMEOUT = 10
  DEFAULT_RENDER_PROCESS_MAX_REQUESTS = 1_000

  RENDER_MODES = {
    subprocess: ReactEmailRails::RenderModes::Subprocess,
    persistent: ReactEmailRails::RenderModes::Persistent,
  }.freeze

  KEY_TRANSFORMS = {
    camel: ->(key) { key.to_s.camelize },
    lower_camel: ->(key) { key.to_s.camelize(:lower) },
    dash: ->(key) { key.to_s.underscore.dasherize },
    snake: ->(key) { key.to_s.underscore },
    none: ->(key) { key },
  }.freeze

  DEFAULT_RENDER_COMMAND = lambda do
    if Rails.env.development?
      [Rails.root.join(DEV_RENDER_BIN).to_s]
    else
      ["node", Rails.root.join(BUNDLE_PATH).to_s]
    end
  end

  DEFAULT_VERIFY_RENDER_ON_BOOT = false

  attr_accessor(
    :component_path_resolver,
    :render_options,
    :transform_props,
    :on_render_error,
    :verify_render_on_boot,
  )
  attr_reader(
    :render_mode,
    :render_timeout,
    :render_process_max_requests,
  )

  class << self
    def default
      new.tap do |config|
        config.component_path_resolver = ->(mailer:, action:) { "#{mailer}/#{action}" }
        config.render_mode = :subprocess
        config.render_options = {}
        config.render_timeout = DEFAULT_RENDER_TIMEOUT
        config.render_process_max_requests = DEFAULT_RENDER_PROCESS_MAX_REQUESTS
        config.transform_props = :lower_camel
        config.on_render_error = nil
        config.verify_render_on_boot = DEFAULT_VERIFY_RENDER_ON_BOOT
      end
    end
  end

  def verify_render_on_boot?
    verify_render_on_boot.respond_to?(:call) ? !!verify_render_on_boot.call : !!verify_render_on_boot
  end

  def render_mode=(value)
    if (value.is_a?(Symbol) || value.is_a?(String)) && !RENDER_MODES.key?(value.to_sym)
      raise(ArgumentError, "Unknown react-email-rails render mode: #{value.inspect}")
    end

    @render_mode = value
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

  def resolved_render_mode
    return render_mode unless render_mode.is_a?(Symbol) || render_mode.is_a?(String)

    RENDER_MODES.fetch(render_mode.to_sym) do
      raise(ArgumentError, "Unknown react-email-rails render mode: #{render_mode.inspect}")
    end
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

    deep_camelize_keys(value.as_json)
  end

  private

  def resolved_render_command
    DEFAULT_RENDER_COMMAND.call
  end

  def serialize_props(props)
    deep_transform_keys(props.as_json, key_transform)
  end

  def key_transform
    transform = transform_props.respond_to?(:to_sym) ? transform_props.to_sym : transform_props

    KEY_TRANSFORMS.fetch(transform) do
      raise(ArgumentError, "Unknown react-email-rails prop transform: #{transform_props.inspect}")
    end
  end

  def deep_transform_keys(value, transform)
    case value
    when Array
      value.map { |item| deep_transform_keys(item, transform) }
    when Hash
      value.transform_keys { |key| transform.call(key) }.transform_values { |item| deep_transform_keys(item, transform) }
    else
      value
    end
  end

  def deep_camelize_keys(value)
    case value
    when Array
      value.map { |item| deep_camelize_keys(item) }
    when Hash
      value.transform_keys { |key| key.to_s.camelize(:lower) }.transform_values { |item| deep_camelize_keys(item) }
    else
      value
    end
  end
end
