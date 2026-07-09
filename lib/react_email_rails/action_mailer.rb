module ReactEmailRails::ActionMailer
  extend(ActiveSupport::Concern)

  SHARED_FILTER_OPTIONS = [:if, :unless, :only, :except].freeze

  prepended do
    class_attribute(:react_email_use_instance_props, default: false)
  end

  class_methods do
    def use_react_instance_props
      self.react_email_use_instance_props = true
    end

    def react_share(hash = nil, **props, &block)
      options = props.slice(*SHARED_FILTER_OPTIONS)
      data = hash || props.except(*SHARED_FILTER_OPTIONS)

      before_action(**options) do
        react_email_append_shared(data, block)
      end
    end
  end

  def react_share(hash = nil, **props, &block)
    react_email_append_shared(hash || props, block)
  end

  def mail(headers = {}, &block)
    return super unless headers.is_a?(Hash)
    return super if headers.empty? && @_mail_was_called

    react = headers.key?(:react) ? headers[:react] : compute_default(self.class.default[:react])
    return super unless react

    props = headers[:props]
    deep_merge = headers[:deep_merge]
    headers = headers.except(:react, :props, :deep_merge)

    component, resolved_props = ReactEmailRails::PropsResolver.new(self).resolve(react, props)
    resolved_props = ReactEmailRails::SharedProps.new(self).merge_into(
      resolved_props,
      deep_merge: react_email_deep_merge?(deep_merge),
    )

    super(headers) do |format|
      rendered = react_email_render(component, resolved_props)

      format.html { rendered.html }
      format.text { rendered.text } if rendered.text.present?

      yield(format) if block
    end
  end

  private

  def assign_headers_to_message(message, headers)
    super(message, headers.except(:react, :props, :deep_merge))
  end

  def react_email_render(component, props)
    props = ReactEmailRails::MailerContext.new(self).merge_into(props)
    render_options = ReactEmailRails.configuration.resolve_render_options(self)
    ReactEmailRails.render(component:, props:, render_options:)
  end

  def react_email_append_shared(data, block)
    store = (@_react_email_shared ||= [])
    store << data.dup.freeze if data.present?
    store << block if block
  end

  def react_email_deep_merge?(override)
    return ReactEmailRails.configuration.deep_merge_shared_props if override.nil?

    override
  end
end
