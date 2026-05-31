class ReactEmailRails::RenderModes::Subprocess
  class << self
    def healthy?(command:, timeout:)
      result = CommandRunner.capture([*command, "--health"], timeout:)
      result.status.success? && ReactEmailRails::RenderProtocol.compatible_response?(JSON.parse(result.stdout))
    rescue StandardError
      false
    end
  end

  def initialize(component:, props:, render_options: {})
    @component = component
    @props = props
    @render_options = render_options
  end

  def render
    run
  end

  private

  attr_reader(:component, :props, :render_options)

  def run
    result = capture(payload_json)
    raise(render_error(error_message(result.stderr, result.status))) unless result.status.success?

    body = JSON.parse(result.stdout)
    validate_response!(body)
    ReactEmailRails::RenderedEmail.new(html: body.fetch("html"), text: body["text"].to_s)
  rescue JSON::ParserError => e
    raise(render_error("render process returned invalid JSON: #{e.message}"))
  rescue KeyError => e
    raise(render_error("render process returned an invalid response: missing #{e.key.inspect}"))
  end

  def capture(input)
    validate_command!
    CommandRunner.capture(command, input:, timeout: render_timeout)
  rescue Timeout::Error
    raise(render_error("render process timed out after #{render_timeout}s"))
  rescue Errno::ENOENT
    raise(render_error("render command not found: #{command.inspect}"))
  end

  def command
    @command ||= ReactEmailRails.configuration.send(:resolved_render_command)
  end

  def render_timeout
    ReactEmailRails.configuration.render_timeout
  end

  def payload
    @payload ||= begin
      payload = {
        component:,
        props: ReactEmailRails.configuration.send(:serialize_props, props),
      }
      payload[:renderOptions] = render_options if render_options.present?
      payload
    end
  end

  def payload_json
    @payload_json ||= JSON.generate(payload)
  end

  def error_message(stderr, status)
    stderr.to_s.strip.presence || "render process exited with #{status}"
  end

  def validate_command!
    command_path = command.first.to_s
    bundle_path = command[1].to_s

    if command_path.end_with?(ReactEmailRails::Configuration::DEV_RENDER_BIN) && !File.exist?(command_path)
      raise(render_error("development renderer not found at #{command_path.inspect}; install JavaScript dependencies with npm, pnpm, yarn, or bun"))
    end

    return unless command_path == "node" && bundle_path.end_with?(ReactEmailRails::Configuration::BUNDLE_PATH)
    return if File.file?(bundle_path)

    raise(render_error("email bundle not found at #{bundle_path.inspect}; run vite build before rendering React emails"))
  end

  def validate_response!(body)
    raise(render_error(ReactEmailRails::RenderProtocol.mismatch_message(body))) unless ReactEmailRails::RenderProtocol.compatible_metadata?(body)

    raise(KeyError.new(key: "html")) unless body.key?("html")
    raise(render_error("render process returned an invalid response: html must be a string")) unless body["html"].is_a?(String)
    raise(render_error("render process returned an invalid response: text must be a string")) if body.key?("text") && !body["text"].is_a?(String)
  end

  def render_error(message)
    ReactEmailRails::RenderError.new("React Email render failed for #{component}: #{message}")
  end
end
