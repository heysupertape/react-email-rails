require("json")
require("open3")
require("timeout")
require("active_support/concern")
require("active_support/notifications")
require("active_support/core_ext/object/blank")
require("active_support/core_ext/object/json")
require("active_support/inflector")
require("rails/railtie")

module ReactEmailRails; end

require_relative("react_email_rails/version")
require_relative("react_email_rails/render_protocol")
require_relative("react_email_rails/action_mailer")
require_relative("react_email_rails/render_error")
require_relative("react_email_rails/rendered_email")
require_relative("react_email_rails/render_modes")
require_relative("react_email_rails/render_modes/subprocess")
require_relative("react_email_rails/render_modes/subprocess/command_runner")
require_relative("react_email_rails/render_modes/persistent")
require_relative("react_email_rails/render_modes/persistent/server")
require_relative("react_email_rails/render_modes/persistent/command_runner")
require_relative("react_email_rails/configuration")
require_relative("react_email_rails/tasks")
require_relative("react_email_rails/props_resolver")
require_relative("react_email_rails/railtie")

module ReactEmailRails
  class << self
    def configuration
      @configuration ||= Configuration.default
    end

    def configure
      yield(configuration)
    end

    def render(component:, props:, render_options: configuration.resolve_render_options)
      ActiveSupport::Notifications.instrument("render.react-email-rails", component:) do |payload|
        configuration.resolved_render_mode.new(component:, props:, render_options:).render.tap do |rendered|
          payload[:html_bytes] = rendered.html.bytesize
        end
      end
    rescue ReactEmailRails::RenderError => e
      configuration.on_render_error&.call(e, component:)
      raise
    end

    def healthy?
      configuration.resolved_render_mode.healthy?(
        command: configuration.send(:resolved_render_command),
        timeout: configuration.render_timeout,
      )
    rescue StandardError
      false
    end
  end
end
