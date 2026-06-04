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
      payload = { component:, props: configuration.send(:serialize_props, props) }
      payload[:renderOptions] = render_options if render_options.present?

      instrument(kind: "email", component:) do
        configuration.resolved_render_mode.new(payload:, label: component).render
      end
    rescue ReactEmailRails::RenderError => e
      configuration.on_render_error&.call(e, kind: "email", component:)
      raise
    end

    # Render an @react-email/editor document (Tiptap JSON) to HTML+text. The document
    # is sent verbatim (its keys are structural); only context is key-transformed, like props.
    def compose(type:, document:, context: {}, preview: nil)
      payload = {
        kind: "document",
        type:,
        document: document.as_json,
        context: configuration.send(:serialize_props, context),
        preview:,
      }

      instrument(kind: "document", type:) do
        configuration.resolved_render_mode.new(payload:, label: type).render
      end
    rescue ReactEmailRails::RenderError => e
      configuration.on_render_error&.call(e, kind: "document", type:)
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

    private

    def instrument(**payload)
      ActiveSupport::Notifications.instrument("render.react-email-rails", **payload) do |event|
        yield.tap do |rendered|
          event[:html_bytes] = rendered.html.bytesize
          event[:warnings] = rendered.warnings if rendered.warnings.present?
        end
      end
    end
  end
end
