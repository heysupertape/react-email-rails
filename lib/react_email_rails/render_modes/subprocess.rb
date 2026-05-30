class ReactEmailRails::RenderModes::Subprocess
  class CommandRunner
    Result = Data.define(:stdout, :stderr, :status)

    class << self
      def capture(command, input: nil, timeout:)
        new(command:, input:, timeout:).capture
      end
    end

    def initialize(command:, input:, timeout:)
      @command = command
      @input = input
      @timeout = timeout
    end

    def capture
      Open3.popen3(*command) do |stdin, stdout, stderr, wait_thread|
        out_reader = read_async(stdout)
        err_reader = read_async(stderr)

        write_input(stdin)

        if wait_thread.join(timeout).nil?
          Process.kill("KILL", wait_thread.pid)
          wait_thread.join
          out_reader.kill
          err_reader.kill
          raise(Timeout::Error)
        end

        Result.new(stdout: out_reader.value, stderr: err_reader.value, status: wait_thread.value)
      end
    end

    private

    attr_reader(:command, :input, :timeout)

    def read_async(io)
      Thread.new { io.read }.tap { |thread| thread.report_on_exception = false }
    end

    def write_input(stdin)
      stdin.write(input) if input
    rescue Errno::EPIPE
      nil
    ensure
      stdin.close
    end
  end

  class << self
    def healthy?(command:, timeout:)
      result = CommandRunner.capture([*command, "--health"], timeout:)
      result.status.success? && JSON.parse(result.stdout)["ok"] == true
    rescue StandardError
      false
    end
  end

  def initialize(component:, props:, cache: nil, render_options: {})
    @component = component
    @props = props
    @cache = cache
    @render_options = render_options
  end

  def render
    if (cache_options = cache_options_hash)
      cache_store.fetch(cache_key, **cache_options) { run }
    else
      run
    end
  end

  private

  attr_reader(:component, :props, :cache, :render_options)

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
    @command ||= ReactEmailRails.configuration.resolved_render_command
  end

  def render_timeout
    ReactEmailRails.configuration.render_timeout
  end

  def payload
    @payload ||= begin
      payload = {
        component:,
        props: ReactEmailRails.configuration.transform_props(props),
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

  def cache_options_hash
    case cache
    when true then {}
    when Hash then cache
    end
  end

  def cache_key
    version = ReactEmailRails.configuration.resolved_cache_version
    ["react-email-rails", version, Digest::SHA256.hexdigest(payload_json)].compact.join("/")
  end

  def cache_store
    ReactEmailRails.configuration.resolved_cache_store
  end
end
