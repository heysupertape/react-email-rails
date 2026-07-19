class ReactEmailRails::MailerContext
  MESSAGE_FIELDS = [:subject, :to, :cc, :bcc, :from, :reply_to].freeze

  def initialize(mailer)
    @mailer = mailer
  end

  def merge_into(props)
    serialized_props = props.as_json
    return props unless serialized_props.is_a?(Hash)

    to_h.merge(serialized_props)
  end

  def to_h
    {
      "mailer" => mailer_context,
      "message" => message_context,
    }
  end

  private

  attr_reader(:mailer)

  def mailer_context
    {
      "mailer_name" => mailer.class.mailer_name,
      "action_name" => mailer.action_name,
    }
  end

  def message_context
    message = mailer.message

    MESSAGE_FIELDS.to_h do |field|
      [field.to_s, message.public_send(field)]
    end
  end
end
