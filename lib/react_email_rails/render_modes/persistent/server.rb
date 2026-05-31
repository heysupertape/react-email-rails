class ReactEmailRails::RenderModes::Persistent::Server
  STDERR_LIMIT = 8 * 1024

  Status = Data.define(:success) do
    def success? = success
  end

  def initialize(command)
    @command = command
    @mutex = Mutex.new
    @stderr_buffer = +""
    @stderr_mutex = Mutex.new
    @stdout_buffer = +""
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
      terminate_process("TERM", @wait_thread.pid)
      @wait_thread.join(1)
      terminate_process("KILL", @wait_thread.pid) if @wait_thread.alive?
    end
  rescue Errno::ESRCH, Errno::EPERM
    nil
  ensure
    [@stdin, @stdout, @stderr].compact.each { |io| io.close unless io.closed? }
    @stderr_reader&.kill
    @stdin = @stdout = @stderr = @wait_thread = @stderr_reader = nil
    @stdout_buffer.clear
  end

  # Release this process's copy of an inherited child's pipes without signalling
  # the process itself, which is still owned by the parent that started it.
  def abandon
    [@stdin, @stdout, @stderr].compact.each { |io| io.close unless io.closed? }
    @stdin = @stdout = @stderr = @wait_thread = @stderr_reader = nil
    @stdout_buffer.clear
  rescue IOError
    nil
  end

  private

  attr_reader(:command)

  def capture_once(input:, timeout:)
    response = request(input, timeout:)
    return failure(response["error"].to_s.presence || "render process failed") unless response["ok"]

    success(JSON.generate(
      {
        protocolVersion: response["protocolVersion"],
        packageVersion: response["packageVersion"],
      }.tap do |body|
        body[:html] = response["html"] if response.key?("html")
        body[:text] = response["text"] if response.key?("text")
      end,
    ))
  rescue JSON::ParserError => e
    failure("render process returned invalid JSON: #{e.message}")
  end

  def health_check_once(timeout:)
    response = request(JSON.generate(health: true), timeout:)
    response["ok"] ? success(JSON.generate(response)) : failure(response["error"].to_s.presence || "render process failed")
  rescue JSON::ParserError => e
    failure("render process returned invalid JSON: #{e.message}")
  end

  def start
    @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(*command, "--persistent", pgroup: true)
    @stderr_buffer = +""
    @stdout_buffer = +""
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
    deadline = monotonic_time + timeout
    line = +""

    loop do
      if (buffered_line = consume_buffered_response_line)
        line << buffered_line
        return line
      end

      line << @stdout_buffer
      @stdout_buffer.clear

      remaining = deadline - monotonic_time
      if remaining <= 0 || IO.select([@stdout], nil, nil, remaining).nil?
        stop
        raise(Timeout::Error)
      end

      begin
        @stdout_buffer << @stdout.read_nonblock(16 * 1024)
      rescue IO::WaitReadable
        next
      end
    end
  rescue EOFError
    line.presence
  end

  def consume_buffered_response_line
    separator = @stdout_buffer.index("\n")
    return unless separator

    @stdout_buffer.slice!(0, separator + 1)
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def terminate_process(signal, pid)
    Process.kill(signal, -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
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
