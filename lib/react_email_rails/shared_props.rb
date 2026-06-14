# Collects props registered with `react_email_share` and merges them beneath the
# per-mail props, which win on conflict. Mirrors inertia-rails shared data.
class ReactEmailRails::SharedProps
  IVAR = :@_react_email_shared

  def initialize(mailer)
    @mailer = mailer
  end

  # Returns `props` untouched when nothing is shared, so non-Hash inputs (e.g.
  # serializers) still flow straight through to serialization.
  def merge_into(props, deep_merge:)
    shared = to_h
    return props if shared.empty?

    base = shared.as_json
    incoming = props.as_json
    deep_merge ? base.deep_merge(incoming) : base.merge(incoming)
  end

  def to_h
    entries.each_with_object({}) do |entry, props|
      props.merge!(resolve(entry))
    end
  end

  private

  attr_reader(:mailer)

  def entries
    mailer.instance_variable_get(IVAR) || []
  end

  # An entry is either a static Hash or a block evaluated at render time. Callable
  # values inside a Hash are evaluated too, so `unread_count: -> { ... }` works.
  def resolve(entry)
    hash = entry.respond_to?(:call) ? mailer.instance_exec(&entry) : entry

    (hash || {}).transform_values do |value|
      value.respond_to?(:call) ? mailer.instance_exec(&value) : value
    end
  end
end
