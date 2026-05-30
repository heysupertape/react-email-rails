class ReactEmailRails::RenderModes::Persistent < ReactEmailRails::RenderModes::Subprocess
  class CommandRunner
    Status = Data.define(:success) do
      def success? = success
    end

    class << self
      def capture(command, input:, timeout:, max_requests: nil)
        server_for(command).capture(input:, timeout:, max_requests:)
      end

      def healthy?(command, timeout:)
        result = server_for(command).health_check(timeout:)
        result.status.success? && JSON.parse(result.stdout)["ok"] == true
      rescue StandardError
        false
      end

      def stop_all
        @mutex&.synchronize do
          @servers&.each_value(&:stop)
          @servers&.clear
        end
      end

      private

      def server_for(command)
        @mutex ||= Mutex.new

        @mutex.synchronize do
          reset_after_fork
          @servers[command.map(&:to_s)] ||= Server.new(command)
        end
      end

      # A forked child inherits the parent's Server objects and the open pipes to
      # the parent's render processes. Sharing those pipes interleaves requests
      # and responses across processes, so drop them (without killing the
      # parent-owned process) and let this process spawn its own on demand.
      def reset_after_fork
        return if @owner_pid == Process.pid && @servers

        @servers&.each_value(&:abandon)
        @servers = {}
        @owner_pid = Process.pid
      end
    end

    class Server
      STDERR_LIMIT = 8 * 1024

      def initialize(command)
        @command = command
        @mutex = Mutex.new
        @stderr_buffer = +""
        @stderr_mutex = Mutex.new
        @requests = 0
      end

      def capture(input:, timeout:, max_requests:)
        @mutex.synchronize do
          capture_once(input:, timeout:).tap { recycle_if_needed(max_requests) }
        end
      rescue Errno::EPIPE, IOError
        stop
        begin
          @mutex.synchronize do
            capture_once(input:, timeout:).tap { recycle_if_needed(max_requests) }
          end
        rescue Errno::EPIPE, IOError
          failure("render process exited before responding")
        end
      end

      def health_check(timeout:)
        @mutex.synchronize { health_check_once(timeout:) }
      rescue Errno::EPIPE, IOError
        stop
        begin
          @mutex.synchronize { health_check_once(timeout:) }
        rescue Errno::EPIPE, IOError
          failure("render process exited before responding")
        end
      end

      def stop
        if @wait_thread&.alive?
          Process.kill("TERM", @wait_thread.pid)
          @wait_thread.join(1)
          Process.kill("KILL", @wait_thread.pid) if @wait_thread.alive?
        end
      rescue Errno::ESRCH
        nil
      ensure
        [@stdin, @stdout, @stderr].compact.each { |io| io.close unless io.closed? }
        @stderr_reader&.kill
        @stdin = @stdout = @stderr = @wait_thread = @stderr_reader = nil
      end

      # Release this process's copy of an inherited child's pipes without signalling
      # the process itself, which is still owned by the parent that started it.
      def abandon
        [@stdin, @stdout, @stderr].compact.each { |io| io.close unless io.closed? }
        @stdin = @stdout = @stderr = @wait_thread = @stderr_reader = nil
      rescue IOError
        nil
      end

      private

      attr_reader(:command)

      def capture_once(input:, timeout:)
        response = request(input, timeout:)
        return failure(response["error"].to_s.presence || "render process failed") unless response["ok"]

        success(JSON.generate(html: response.fetch("html"), text: response["text"].to_s))
      rescue JSON::ParserError => e
        failure("render process returned invalid JSON: #{e.message}")
      end

      def health_check_once(timeout:)
        response = request(JSON.generate(health: true), timeout:)
        response["ok"] ? success(JSON.generate(ok: true)) : failure(response["error"].to_s.presence || "render process failed")
      rescue JSON::ParserError => e
        failure("render process returned invalid JSON: #{e.message}")
      end

      def start
        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(*command, "--persistent")
        @stderr_buffer = +""
        @requests = 0
        @stderr_reader = Thread.new { drain_stderr }
        @stderr_reader.report_on_exception = false
      end

      def running?
        @wait_thread&.alive?
      end

      def request(input, timeout:)
        start unless running?

        @stdin.write("#{input}\n")
        @stdin.flush

        line = read_response_line(timeout)
        return { "ok" => false, "error" => "render process exited before responding" } unless line

        JSON.parse(line)
      end

      def read_response_line(timeout)
        if IO.select([@stdout], nil, nil, timeout).nil?
          stop
          raise(Timeout::Error)
        end

        @stdout.gets
      end

      def drain_stderr
        @stderr.each do |chunk|
          @stderr_mutex.synchronize do
            @stderr_buffer << chunk
            @stderr_buffer = @stderr_buffer.byteslice(-STDERR_LIMIT, STDERR_LIMIT) if @stderr_buffer.bytesize > STDERR_LIMIT
          end
        end
      rescue IOError
        nil
      end

      def success(stdout)
        ReactEmailRails::RenderModes::Subprocess::CommandRunner::Result.new(
          stdout:,
          stderr: "",
          status: Status.new(true),
        )
      end

      def failure(message)
        ReactEmailRails::RenderModes::Subprocess::CommandRunner::Result.new(
          stdout: "",
          stderr: [message, stderr_buffer].reject(&:blank?).join("\n"),
          status: Status.new(false),
        )
      end

      def stderr_buffer
        @stderr_mutex.synchronize { @stderr_buffer.dup }
      end

      def recycle_if_needed(max_requests)
        return unless max_requests&.positive?

        @requests += 1
        stop if @requests >= max_requests
      end
    end
  end

  class << self
    def healthy?(command:, timeout:)
      CommandRunner.healthy?(command, timeout:)
    end
  end

  private

  def capture(input)
    CommandRunner.capture(
      command,
      input:,
      timeout: render_timeout,
      max_requests: render_process_max_requests,
    )
  rescue Timeout::Error
    raise(render_error("render process timed out after #{render_timeout}s"))
  rescue Errno::ENOENT
    raise(render_error("render command not found: #{command.inspect}"))
  end

  def render_process_max_requests
    ReactEmailRails.configuration.render_process_max_requests
  end
end

at_exit { ReactEmailRails::RenderModes::Persistent::CommandRunner.stop_all }
