class ReactEmailRails::Renderer::Child
  STDERR_LIMIT = 8 * 1024

  def initialize(command)
    @command = command
    @mutex = Mutex.new
    @stderr_buffer = +""
    @stderr_mutex = Mutex.new
    @stdout_buffer = +""
    @requests = 0
  end

  def exchange(input, timeout:, max_requests:)
    with_retry_on_broken_pipe do
      request(input, timeout:).tap { recycle_if_needed(max_requests) }
    end
  end

  def health_check(timeout:)
    with_retry_on_broken_pipe { request(JSON.generate(health: true), timeout:) }
  end

  def stop
    if @mutex.owned?
      stop_unlocked
    else
      @mutex.synchronize { stop_unlocked }
    end
  end

  def abandon
    release_io
  rescue IOError
    nil
  end

  private

  attr_reader(:command)

  def stop_unlocked
    if @wait_thread&.alive?
      terminate_process("TERM", @wait_thread.pid)
      @wait_thread.join(1)
      terminate_process("KILL", @wait_thread.pid) if @wait_thread.alive?
    end
  rescue Errno::ESRCH, Errno::EPERM
    nil
  ensure
    @stderr_reader&.kill
    release_io
  end

  def release_io
    [@stdin, @stdout, @stderr].compact.each { |io| io.close unless io.closed? }
    @stdin = @stdout = @stderr = @wait_thread = @stderr_reader = nil
    @stdout_buffer.clear
  end

  def with_retry_on_broken_pipe(&block)
    @mutex.synchronize(&block)
  rescue Errno::EPIPE, IOError
    stop
    begin
      @mutex.synchronize(&block)
    rescue Errno::EPIPE, IOError
      failed("render process exited before responding")
    end
  end

  def start
    release_io
    @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(*command, pgroup: true)
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
    return failed("render process exited before responding") unless line

    JSON.parse(line)
  rescue JSON::ParserError => e
    stop
    failed("render process returned invalid JSON: #{e.message}")
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
        silent = line.empty? && @stdout_buffer.empty?
        stop
        raise(Timeout::Error, silent ? unmatched_package_message : "render process timed out")
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

  def unmatched_package_message
    "no response received; gem and npm package react-email-rails must both be #{ReactEmailRails::VERSION}"
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

  def failed(message)
    {
      "ok" => false,
      "error" => [message, stderr_buffer].reject(&:blank?).join("\n"),
    }
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
