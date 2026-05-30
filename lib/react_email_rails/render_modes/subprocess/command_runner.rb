class ReactEmailRails::RenderModes::Subprocess::CommandRunner
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
    Open3.popen3(*command, pgroup: true) do |stdin, stdout, stderr, wait_thread|
      out_reader = read_async(stdout)
      err_reader = read_async(stderr)

      write_input(stdin)

      if wait_thread.join(timeout).nil?
        terminate_process("KILL", wait_thread.pid)
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

  def terminate_process(signal, pid)
    Process.kill(signal, -pid)
  rescue Errno::ESRCH
    nil
  end
end
