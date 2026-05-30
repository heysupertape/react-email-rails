module ReactEmailRails::ActionMailer
  extend(ActiveSupport::Concern)

  prepended do
    class_attribute(:react_email_use_instance_props, default: false)
  end

  class_methods do
    def use_react_instance_props
      self.react_email_use_instance_props = true
    end
  end

  def mail(headers = {}, &block)
    return super unless headers.is_a?(Hash) && headers.key?(:react)

    headers = headers.dup
    react = headers.delete(:react)
    props = headers.delete(:props) if headers.key?(:props)

    component, resolved_props = ReactEmailRails::PropsResolver.new(self).resolve(react, props)
    render_options = ReactEmailRails.configuration.resolve_render_options(self)
    rendered = ReactEmailRails.render(component:, props: resolved_props, render_options:)

    super(headers) do |format|
      format.html { rendered.html }
      format.text { rendered.text } if rendered.text.present?
      yield(format) if block
    end
  end
end
