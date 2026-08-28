ENV["RAILS_ENV"] = "test"

require("bundler/setup")
require("minitest/autorun")
require("rails")
require("action_mailer/railtie")
require("active_support/test_case")
require("fileutils")
require("tmpdir")

require("react-email-rails")

class TestApplication < Rails::Application
  config.eager_load = false
  config.secret_key_base = "test"
  config.action_mailer.delivery_method = :test
  config.action_mailer.perform_caching = false
  config.logger = Logger.new(nil)
end

Rails.application.initialize!

class ApplicationMailer < ActionMailer::Base
  prepend(ReactEmailRails::ActionMailer)
  default(from: "test@example.com")
end

class ActiveSupport::TestCase
  INTERNAL_REACT_EMAIL_CONFIG_METHODS = {
    render_command: :resolved_render_command,
  }.freeze

  # Shared stub-renderer building blocks (RENDER_METADATA mirrors the Ruby<->JS handshake).
  RUBY = RbConfig.ruby
  RENDER_METADATA = "protocolVersion: #{ReactEmailRails::RENDER_PROTOCOL_VERSION}, packageVersion: #{ReactEmailRails::VERSION.inspect}".freeze

  # Echoes the request payload back as the HTML body so tests can assert on it.
  ECHO_INPUT = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      while (line = $stdin.gets)
        $stdout.puts(JSON.generate(ok: true, html: line.chomp, text: "", #{RENDER_METADATA}))
        $stdout.flush
      end
    RUBY
    "--",
  ].freeze

  HEALTH_OK = [
    RUBY,
    "-e",
    <<~RUBY,
      require "json"
      request = JSON.parse($stdin.gets)
      $stdout.puts(JSON.generate(ok: request["health"] == true, #{RENDER_METADATA}))
      $stdout.flush
    RUBY
    "--",
  ].freeze

  def write_destination_file(path, content)
    full_path = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  def with_react_email_config(renderer: nil, **overrides)
    original = overrides.to_h { |key, _value| [key, ReactEmailRails.configuration.public_send(key)] }
    overrides.each { |key, value| ReactEmailRails.configuration.public_send("#{key}=", value) }
    stub_renderer(renderer) if renderer
    yield
  ensure
    restore_renderer if renderer
    original&.each { |key, value| ReactEmailRails.configuration.public_send("#{key}=", value) }
  end

  def stub_renderer(renderer)
    redefine_renderer_class(renderer)
  end

  def restore_renderer
    redefine_renderer_class(ReactEmailRails::Renderer)
  end

  def redefine_renderer_class(klass)
    singleton = class << ReactEmailRails; self; end
    singleton.silence_redefinition_of_method(:renderer_class)
    singleton.define_method(:renderer_class) { klass }
    singleton.send(:private, :renderer_class)
  end

  # Each key maps to a private instance method on Configuration; the singleton override
  # only shadows it, so teardown just removes it and the original re-surfaces.
  def with_react_email_internals(**overrides)
    config = ReactEmailRails.configuration
    singleton = class << config; self; end
    methods = overrides.to_h { |key, value| [INTERNAL_REACT_EMAIL_CONFIG_METHODS.fetch(key), value] }

    methods.each { |method, value| singleton.define_method(method) { value } }

    yield
  ensure
    methods&.each_key { |method| singleton.remove_method(method) }
  end
end
