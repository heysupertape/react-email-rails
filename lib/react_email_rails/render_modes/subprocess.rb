class ReactEmailRails::RenderModes::Subprocess
  class << self
    def healthy?(command:, timeout:)
      result = CommandRunner.capture([*command, "--health"], timeout:)
      result.status.success? && JSON.parse(result.stdout)["ok"] == true
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
    ReactEmailRails::RenderedEmail.new(html: body.fetch("html"), text: body["text"].to_s)
  rescue JSON::ParserError => e
    raise(render_error("render process returned invalid JSON: #{e.message}"))
  end

  def capture(input)
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

  def render_error(message)
    ReactEmailRails::RenderError.new("React Email render failed for #{component}: #{message}")
  end
end
