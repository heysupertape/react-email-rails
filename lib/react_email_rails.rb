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
      payload = { component:, props: serialized_props(props) }
      payload[:renderOptions] = render_options if render_options.present?

      perform(payload:, label: component, kind: "email", component:)
    end

    # The document is sent verbatim (keys are structural); only context is key-transformed, like props.
    def compose(type:, document:, context: {}, preview: nil)
      payload = {
        kind: "document",
        type:,
        document: document.as_json,
        context: serialized_props(context),
        preview:,
      }

      perform(payload:, label: type, kind: "document", type:)
    end

    # Parse semantic HTML or Markdown into an editor document Hash using the renderer's
    # extensions. Pass exactly one of `html:` or `markdown:`.
    def parse(type:, html: nil, markdown: nil, context: {})
      payload = {
        kind: "parse",
        type:,
        context: serialized_props(context),
      }.merge(parse_source(html:, markdown:))

      perform(payload:, label: type, response: :document, kind: "parse", type:)
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

    def perform(payload:, label:, response: :email, **metadata)
      instrument(**metadata) do
        configuration.resolved_render_mode.new(payload:, label:, response:).render
      end
    rescue ReactEmailRails::RenderError => e
      configuration.on_render_error&.call(e, **metadata)
      raise
    end

    # Markdown is converted renderer-side, not here; both inputs are sent as-is.
    def parse_source(html:, markdown:)
      if !html.nil? && !markdown.nil?
        raise(ArgumentError, "ReactEmailRails.parse accepts only one of html: or markdown:")
      end

      return { html: html.to_s } unless html.nil?
      return { markdown: markdown.to_s } unless markdown.nil?

      raise(ArgumentError, "ReactEmailRails.parse requires html: or markdown:")
    end

    def serialized_props(value)
      configuration.send(:serialize_props, value)
    end

    def instrument(**metadata)
      ActiveSupport::Notifications.instrument("render.react-email-rails", **metadata) do |payload|
        yield.tap do |result|
          next unless result.respond_to?(:html)

          payload[:html_bytes] = result.html.bytesize
          payload[:warnings] = result.warnings if result.warnings.present?
        end
      end
    end
  end
end
