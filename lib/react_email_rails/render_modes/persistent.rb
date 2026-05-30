class ReactEmailRails::RenderModes::Persistent < ReactEmailRails::RenderModes::Subprocess
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
    ReactEmailRails.configuration.send(:render_process_max_requests)
  end
end

at_exit { ReactEmailRails::RenderModes::Persistent::CommandRunner.stop_all }
