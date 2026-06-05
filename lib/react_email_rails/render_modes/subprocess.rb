class ReactEmailRails::RenderModes::Subprocess
  class << self
    def healthy?(command:, timeout:)
      result = CommandRunner.capture([*command, "--health"], timeout:)
      result.status.success? && ReactEmailRails::RenderProtocol.compatible_response?(JSON.parse(result.stdout))
    rescue StandardError
      false
    end
  end

  # Payload-agnostic transport: the caller builds and serializes the payload.
  # `label` identifies the render in error messages (component name or document type).
  # `response` selects how the renderer's reply is interpreted: `:email` builds a
  # RenderedEmail (render/compose), `:document` returns the parsed document (parse).
  def initialize(payload:, label:, response: :email)
    @payload = payload
    @label = label
    @response = response
  end

  def render
    run
  end

  private

  attr_reader(:payload, :label, :response)

  def run
    result = capture(payload_json)
    raise(render_error(error_message(result.stderr, result.status))) unless result.status.success?

    body = JSON.parse(result.stdout)
    validate_metadata!(body)
    build_result(body)
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

    raise(render_error("email bundle not found at #{bundle_path.inspect}; run react-email-rails-build before rendering React emails"))
  end

  def validate_metadata!(body)
    return if ReactEmailRails::RenderProtocol.compatible_metadata?(body)

    raise(render_error(ReactEmailRails::RenderProtocol.mismatch_message(body)))
  end

  def build_result(body)
    response == :document ? build_document(body) : build_rendered_email(body)
  end

  def build_rendered_email(body)
    raise(KeyError.new(key: "html")) unless body.key?("html")
    raise(render_error("render process returned an invalid response: html must be a string")) unless body["html"].is_a?(String)
    raise(render_error("render process returned an invalid response: text must be a string")) if body.key?("text") && !body["text"].is_a?(String)

    ReactEmailRails::RenderedEmail.new(html: body.fetch("html"), text: body["text"].to_s, warnings: warnings_from(body))
  end

  def build_document(body)
    raise(KeyError.new(key: "document")) unless body.key?("document")

    document = body.fetch("document")
    raise(render_error("parse process returned an invalid response: document must be an object")) unless document.is_a?(Hash)

    document
  end

  def warnings_from(body)
    warnings = body["warnings"]
    return [] unless warnings.is_a?(Array)

    warnings.filter_map { |warning| warning.transform_keys(&:to_sym) if warning.is_a?(Hash) }
  end

  def render_error(message)
    ReactEmailRails::RenderError.new("React Email render failed for #{label}: #{message}")
  end
end
