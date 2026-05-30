ReactEmailRails.configure do |config|
  # config.cache = ActionMailer::Base.perform_caching
  # config.cache_store = Rails.cache
  # config.cache_version = -> {
  #   bundle = Rails.root.join("tmp/react-email-rails/emails.js")
  #   Digest::SHA256.hexdigest(bundle.read) if bundle.exist?
  # }

  # config.component_path_resolver = ->(mailer:, action:) { "#{mailer}/#{action}" }
  # config.prop_serializer = ->(props:) { props.as_json }
  # config.prop_transformer = ->(props:) { config.deep_camelize_keys(props) }

  # Persistent mode reuses one Node process; it is best for render-heavy worker processes.
  # config.render_mode = :persistent
  # config.render_options = { html: { pretty: Rails.env.development? } }
  # config.render_command = -> { ["node", Rails.root.join("tmp/react-email-rails/emails.js").to_s] }
  # config.render_timeout = 10
  # config.render_process_max_requests = 1_000
  # config.on_render_error = ->(error, component:) { Rails.error.report(error, context: { component: }) }

  # Enable this only in processes that render Action Mailer messages and have the email bundle available.
  # config.verify_render_on_boot = -> { Rails.env.production? }
end
