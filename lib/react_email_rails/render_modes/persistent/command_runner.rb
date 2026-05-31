class ReactEmailRails::RenderModes::Persistent::CommandRunner
  class << self
    def capture(command, input:, timeout:, max_requests: nil)
      server_for(command).capture(input:, timeout:, max_requests:)
    end

    def healthy?(command, timeout:)
      result = server_for(command).health_check(timeout:)
      result.status.success? && ReactEmailRails::RenderProtocol.compatible_response?(JSON.parse(result.stdout))
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
        @servers[command.map(&:to_s)] ||= ReactEmailRails::RenderModes::Persistent::Server.new(command)
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
end
