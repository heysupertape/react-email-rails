module ReactEmailRails::ActionMailer
  extend(ActiveSupport::Concern)

  prepended do
    class_attribute(:react_email_use_assigns, default: false)
  end

  class_methods do
    def use_react_assigns
      self.react_email_use_assigns = true
    end
  end

  def mail(headers = {}, &block)
    return super unless headers.is_a?(Hash) && headers.key?(:react)

    headers = headers.dup
    react = headers.delete(:react)
    props = headers.delete(:props) if headers.key?(:props)

    component, resolved_props = ReactEmailRails::PropsResolver.new(self).resolve(react, props)
    cache = ReactEmailRails.configuration.resolve_cache(self)
    render_options = ReactEmailRails.configuration.resolve_render_options(self)
    rendered = ReactEmailRails.render(component:, props: resolved_props, cache:, render_options:)

    super(headers) do |format|
      format.html { rendered.html }
      format.text { rendered.text } if rendered.text.present?
      yield(format) if block
    end
  end
end
