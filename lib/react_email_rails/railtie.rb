class ReactEmailRails::Railtie < Rails::Railtie
  initializer("react-email-rails.action_mailer") do
    ActiveSupport.on_load(:action_mailer) do
      prepend(ReactEmailRails::ActionMailer)
    end
  end

  rake_tasks { load(File.expand_path("../tasks/react_email_rails/build.rake", __dir__)) }

  config.after_initialize do
    if ReactEmailRails.configuration.verify_render_on_boot? && !ReactEmailRails.healthy?
      Rails.logger.error(
        "[react-email-rails] render verification failed for command: " \
          "#{ReactEmailRails.configuration.send(:resolved_render_command).inspect}",
      )
    end
  end
end
