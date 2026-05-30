class ReactEmailRails::Configuration
  BUNDLE_PATH = "tmp/react-email-rails/emails.js"
  DEV_RENDER_BIN = "node_modules/.bin/react-email-rails-dev"

  DEFAULT_RENDER_TIMEOUT = 10
  DEFAULT_RENDER_PROCESS_MAX_REQUESTS = 1_000

  RENDER_MODES = {
    subprocess: ReactEmailRails::RenderModes::Subprocess,
    persistent: ReactEmailRails::RenderModes::Persistent,
  }.freeze

  DEFAULT_RENDER_COMMAND = lambda do
    if Rails.env.development?
      [Rails.root.join(DEV_RENDER_BIN).to_s]
    else
      ["node", Rails.root.join(BUNDLE_PATH).to_s]
    end
  end

  # Memoized per process: the bundle only changes on deploy, which starts a fresh
  # process. Avoids re-reading and hashing the whole bundle on every cached render.
  DEFAULT_CACHE_VERSION = lambda do
    @default_cache_version ||= begin
      bundle = Rails.root.join(BUNDLE_PATH)
      Digest::SHA256.hexdigest(bundle.read) if bundle.exist?
    end
  end

  DEFAULT_VERIFY_RENDER_ON_BOOT = -> { Rails.env.production? }

  attr_accessor(
    :cache,
    :cache_store,
    :cache_version,
    :component_path_resolver,
    :prop_serializer,
    :prop_transformer,
    :render_mode,
    :render_options,
    :render_command,
    :render_timeout,
    :render_process_max_requests,
    :on_render_error,
    :verify_render_on_boot,
  )

  class << self
    def default
      new.tap do |config|
        config.cache = ActionMailer::Base.perform_caching
        config.cache_store = Rails.cache
        config.cache_version = DEFAULT_CACHE_VERSION
        config.component_path_resolver = ->(mailer:, action:) { "#{mailer}/#{action}" }
        config.prop_serializer = ->(props:) { props.as_json }
        config.prop_transformer = ->(props:) { config.deep_camelize_keys(props) }
        config.render_mode = :subprocess
        config.render_options = {}
        config.render_command = DEFAULT_RENDER_COMMAND
        config.render_timeout = DEFAULT_RENDER_TIMEOUT
        config.render_process_max_requests = DEFAULT_RENDER_PROCESS_MAX_REQUESTS
        config.on_render_error = nil
        config.verify_render_on_boot = DEFAULT_VERIFY_RENDER_ON_BOOT
      end
    end
  end

  def verify_render_on_boot?
    verify_render_on_boot.respond_to?(:call) ? !!verify_render_on_boot.call : !!verify_render_on_boot
  end

  def resolved_render_command
    render_command.respond_to?(:call) ? render_command.call : render_command
  end

  def resolved_render_mode
    return render_mode unless render_mode.is_a?(Symbol) || render_mode.is_a?(String)

    RENDER_MODES.fetch(render_mode.to_sym) do
      raise(ArgumentError, "Unknown react-email-rails render mode: #{render_mode.inspect}")
    end
  end

  def transform_props(props)
    prop_transformer.call(props: prop_serializer.call(props:))
  end

  def resolve_cache(context = nil)
    return context.instance_exec(&cache) if cache.respond_to?(:call) && context
    return cache.call if cache.respond_to?(:call)

    cache
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

  def resolved_cache_version
    cache_version.respond_to?(:call) ? cache_version.call : cache_version
  end

  def resolved_cache_store
    cache_store || Rails.cache
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
