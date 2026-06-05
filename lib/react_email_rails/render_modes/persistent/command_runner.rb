class ReactEmailRails::RenderModes::Persistent::CommandRunner
  # Eager (not lazy) so concurrent first renders can't each create separate Mutexes.
  @mutex = Mutex.new

  class << self
    def capture(command, input:, timeout:, max_requests: nil)
      server_for(command).capture(input:, timeout:, max_requests:)
    end

    def healthy?(command, timeout:)
      result = server_for(command).health_check(timeout:)
      ReactEmailRails::RenderProtocol.healthy_result?(result)
    rescue StandardError
      false
    end

    def stop_all
      @mutex.synchronize do
        @servers&.each_value(&:stop)
        @servers&.clear
      end
    end

    private

    def server_for(command)
      @mutex.synchronize do
        reset_after_fork
        @servers[command.map(&:to_s)] ||= ReactEmailRails::RenderModes::Persistent::Server.new(command)
      end
    end

    # A forked child inherits the parent's Servers and their open pipes; sharing those pipes
    # interleaves requests across processes, so drop them without killing the parent's process.
    def reset_after_fork
      return if @owner_pid == Process.pid && @servers

      @servers&.each_value(&:abandon)
      @servers = {}
      @owner_pid = Process.pid
    end
  end
end
