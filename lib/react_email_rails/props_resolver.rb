class ReactEmailRails::PropsResolver
  INTERNAL_ASSIGN_PREFIX = "_"
  # Some Action Mailer framework assigns do not use the internal `_` prefix.
  RESERVED_ASSIGNS = ["params", "rendered_format"].freeze

  def initialize(mailer)
    @mailer = mailer
  end

  def resolve(react, props)
    case react
    when String
      [react, props || {}]
    when Hash
      raise(ArgumentError, "Parameter `props` is not allowed when passing a Hash to `react`") if props

      [inferred_component, react]
    when true
      [inferred_component, assign_props]
    else
      raise(ArgumentError, "`react` must be a String, Hash, or true")
    end
  end

  private

  attr_reader(:mailer)

  def inferred_component
    ReactEmailRails.configuration.component_path_resolver.call(
      mailer: mailer.class.mailer_name,
      action: mailer.action_name,
    )
  end

  def assign_props
    # `react: true` infers the component name; instance vars become props only when the
    # mailer opts in. Without it, the component renders with no props.
    return {} unless mailer.class.react_email_use_instance_props

    mailer.instance_variables.each_with_object({}) do |ivar, props|
      name = ivar.to_s.delete_prefix("@")
      next if name.start_with?(INTERNAL_ASSIGN_PREFIX) || RESERVED_ASSIGNS.include?(name)

      props[name] = mailer.instance_variable_get(ivar)
    end
  end
end
