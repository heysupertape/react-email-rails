class ReactEmailRails::RenderModes::Persistent < ReactEmailRails::RenderModes::Subprocess
  class << self
    def healthy?(command:, timeout:)
      CommandRunner.healthy?(command, timeout:)
    end
  end

  private

  def capture(input)
    with_capture_rescues do
      CommandRunner.capture(
        command,
        input:,
        timeout: render_timeout,
        max_requests: render_process_max_requests,
      )
    end
  end

  def render_process_max_requests
    ReactEmailRails.configuration.render_process_max_requests
  end
end

at_exit { ReactEmailRails::RenderModes::Persistent::CommandRunner.stop_all }
