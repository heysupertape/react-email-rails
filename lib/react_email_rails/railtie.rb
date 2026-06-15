class ReactEmailRails::Railtie < Rails::Railtie
  initializer("react-email-rails.action_mailer") do
    ActiveSupport.on_load(:action_mailer) do
      prepend(ReactEmailRails::ActionMailer)
      register_preview_interceptor(ReactEmailRails::PreviewLiveReload) if Rails.env.development?
    end
  end

  rake_tasks { load(File.expand_path("../tasks/react_email_rails/build.rake", __dir__)) }
end
