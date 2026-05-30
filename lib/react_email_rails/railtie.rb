class ReactEmailRails::Railtie < Rails::Railtie
  initializer("react-email-rails.action_mailer") do
    ActiveSupport.on_load(:action_mailer) do
      prepend(ReactEmailRails::ActionMailer)
    end
  end

  config.after_initialize do
    if ReactEmailRails.configuration.verify_render_on_boot? && !ReactEmailRails.healthy?
      Rails.logger.error(
        "[react-email-rails] render verification failed for command: " \
          "#{ReactEmailRails.configuration.resolved_render_command.inspect}",
      )
    end
  end
end
