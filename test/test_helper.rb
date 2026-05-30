ENV["RAILS_ENV"] = "test"

require("bundler/setup")
require("minitest/autorun")
require("rails")
require("action_mailer/railtie")
require("active_support/test_case")
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
    render_process_max_requests: :render_process_max_requests,
  }.freeze

  def with_react_email_config(**overrides)
    original = overrides.to_h { |key, _value| [key, ReactEmailRails.configuration.public_send(key)] }
    overrides.each { |key, value| ReactEmailRails.configuration.public_send("#{key}=", value) }
    yield
  ensure
    original&.each { |key, value| ReactEmailRails.configuration.public_send("#{key}=", value) }
  end

  def with_react_email_internals(**overrides)
    config = ReactEmailRails.configuration
    singleton = class << config; self; end
    original_methods = overrides.to_h do |key, _value|
      method = INTERNAL_REACT_EMAIL_CONFIG_METHODS.fetch(key)
      [
        method,
        {
          singleton: singleton.method_defined?(method, false) ||
            singleton.private_method_defined?(method, false) ||
            singleton.protected_method_defined?(method, false),
          method: config.method(method),
        },
      ]
    end

    overrides.each do |key, value|
      method = INTERNAL_REACT_EMAIL_CONFIG_METHODS.fetch(key)
      singleton.define_method(method) { value }
    end

    yield
  ensure
    original_methods&.each do |method, original|
      singleton.remove_method(method) if singleton.method_defined?(method, false)
      singleton.remove_method(method) if singleton.private_method_defined?(method, false)
      singleton.remove_method(method) if singleton.protected_method_defined?(method, false)

      next unless original[:singleton]

      original_method = original[:method]
      singleton.define_method(method) { |*args, **kwargs, &block| original_method.call(*args, **kwargs, &block) }
    end
  end
end
