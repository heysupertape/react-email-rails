ENV["RAILS_ENV"] = "test"

require("bundler/setup")
require("minitest/autorun")
require("rails")
require("action_mailer/railtie")
require("active_support/cache")
require("active_support/test_case")
require("tmpdir")

require("react-email-rails")

class TestApplication < Rails::Application
  config.eager_load = false
  config.secret_key_base = "test"
  config.cache_store = :memory_store
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
  def with_react_email_config(**overrides)
    original = overrides.to_h { |key, _value| [key, ReactEmailRails.configuration.public_send(key)] }
    overrides.each { |key, value| ReactEmailRails.configuration.public_send("#{key}=", value) }
    yield
  ensure
    original&.each { |key, value| ReactEmailRails.configuration.public_send("#{key}=", value) }
  end
end
