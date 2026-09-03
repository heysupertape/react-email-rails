class ReactEmailRails::Renderer
  class << self
    def healthy?(command:, timeout:)
      body = child_for(command).health_check(timeout:)
      ReactEmailRails::RenderProtocol.compatible_response?(body)
    rescue StandardError
      false
    end

    def stop_all
      @mutex.synchronize do
        @children&.each_value(&:stop)
        @children&.clear
      end
    end

    private

    def exchange(command, input, timeout:, max_requests:)
      child_for(command).exchange(input, timeout:, max_requests:)
    end

    def child_for(command)
      @mutex.synchronize do
        reset_after_fork
        @children[command.map(&:to_s)] ||= Child.new(command)
      end
    end

    def reset_after_fork
      return if @owner_pid == Process.pid && @children

      @children&.each_value(&:abandon)
      @children = {}
      @owner_pid = Process.pid
    end
  end

  @mutex = Mutex.new

  def initialize(payload:, label:)
    @payload = payload
    @label = label
  end

  def render
    body = exchange
    raise(render_error(error_message(body["error"]))) unless body["ok"]

    validate_metadata!(body)
    build_rendered_email(body)
  rescue KeyError => e
    raise(render_error("render process returned an invalid response: missing #{e.key.inspect}"))
  end

  private

  attr_reader(:payload, :label)

  def exchange
    with_capture_rescues do
      validate_command!
      self.class.send(
        :exchange,
        command,
        payload_json,
        timeout: render_timeout,
        max_requests: render_process_max_requests,
      )
    end
  end

  def with_capture_rescues
    yield
  rescue Timeout::Error => e
    detail = e.message
    suffix =
      if detail.present? && detail != "Timeout::Error" && detail != "execution expired"
        " (#{detail})"
      else
        ""
      end
    raise(render_error("render process timed out after #{render_timeout}s#{suffix}"))
  rescue Errno::ENOENT
    raise(render_error("render command not found: #{command.inspect}"))
  end

  def command
    @command ||= ReactEmailRails.configuration.send(:resolved_render_command)
  end

  def render_timeout
    ReactEmailRails.configuration.render_timeout
  end

  def render_process_max_requests
    ReactEmailRails.configuration.render_process_max_requests
  end

  def payload_json
    @payload_json ||= JSON.generate(payload)
  end

  def error_message(message)
    message.to_s.strip.presence || "render process failed"
  end

  def validate_command!
    script = command[1].to_s
    return if File.file?(script)

    if script.end_with?(ReactEmailRails::Configuration::DEV_RENDER_SCRIPT)
      raise(render_error("development renderer not found at #{script.inspect}; install JavaScript dependencies with npm, pnpm, yarn, or bun"))
    end

    return unless script.end_with?(ReactEmailRails::Configuration::BUNDLE_PATH)

    raise(render_error("email bundle not found at #{script.inspect}; run react-email-rails-build before rendering React emails"))
  end

  def validate_metadata!(body)
    return if ReactEmailRails::RenderProtocol.compatible_metadata?(body)

    raise(render_error(ReactEmailRails::RenderProtocol.mismatch_message(body)))
  end

  def build_rendered_email(body)
    raise(KeyError.new(key: "html")) unless body.key?("html")
    raise(render_error("render process returned an invalid response: html must be a string")) unless body["html"].is_a?(String)
    raise(render_error("render process returned an invalid response: text must be a string")) if body.key?("text") && !body["text"].is_a?(String)

    ReactEmailRails::RenderedEmail.new(html: body.fetch("html"), text: body["text"].to_s)
  end

  def render_error(message)
    ReactEmailRails::RenderError.new("React Email render failed for #{label}: #{message}")
  end
end

at_exit { ReactEmailRails::Renderer.stop_all }
