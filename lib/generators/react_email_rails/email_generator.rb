require("rails/generators/named_base")
require("json")
require("open3")
require("timeout")
require_relative("vite_config_files")

module ReactEmailRails; end
module ReactEmailRails::Generators; end

class ReactEmailRails::Generators::EmailGenerator < Rails::Generators::NamedBase
  CONFIG_BIN = "node_modules/.bin/react-email-rails-config"

  source_root(File.expand_path("templates/email", __dir__))

  argument(:actions, type: :array, default: [], banner: "method method")

  class_option(
    :skip_preview,
    type: :boolean,
    default: false,
    desc: "Skip creating the mailer preview",
  )
  class_option(
    :skip_test,
    type: :boolean,
    default: false,
    desc: "Skip creating the mailer test",
  )
  class_option(
    :emails_path,
    type: :string,
    desc: "Directory containing React Email components",
  )
  class_option(
    :extension,
    type: :string,
    desc: "React Email component extension, such as tsx or jsx",
  )

  check_class_collision(suffix: "Mailer")

  def create_mailer_file
    template("mailer.rb", File.join("app/mailers", class_path, "#{file_name}_mailer.rb"))

    in_root do
      if behavior == :invoke && !File.exist?(application_mailer_file_name)
        template("application_mailer.rb", application_mailer_file_name)
      end
    end
  end

  def copy_email_components
    empty_directory(component_base_path)

    actions.each do |action|
      @action = action
      @component_name = action.camelize
      @path = File.join(component_base_path, "#{action}#{component_extension}")
      template("component.tsx", @path)
    end
  end

  def create_test_file
    return if options[:skip_test]

    template("mailer_test.rb", File.join("test/mailers", class_path, "#{file_name}_mailer_test.rb"))
  end

  def create_preview_file
    return if options[:skip_preview]

    template("mailer_preview.rb", File.join("test/mailers/previews", class_path, "#{file_name}_mailer_preview.rb"))
  end

  private

  def file_name
    @_file_name ||= super.sub(/_mailer\z/i, "")
  end

  def mailer_file_path
    "#{file_path}_mailer"
  end

  def component_base_path
    File.join(emails_path, mailer_file_path)
  end

  def emails_path
    @emails_path ||= normalize_emails_path(
      options[:emails_path].presence ||
        vite_plugin_metadata.dig("emails", "path") ||
        emails_path_from_vite_config ||
        "app/javascript/emails",
    )
  end

  def component_extension
    @component_extension ||= normalize_extension(
      options[:extension].presence ||
        vite_plugin_metadata.dig("emails", "extensions")&.first ||
        extension_from_vite_config ||
        extension_from_existing_email_components ||
        extension_from_existing_app_components ||
        extension_from_typescript_signal ||
        ".tsx",
    )
  end

  def application_mailer_file_name
    @_application_mailer_file_name ||= if mountable_engine?
      "app/mailers/#{namespaced_path}/application_mailer.rb"
    else
      "app/mailers/application_mailer.rb"
    end
  end

  def vite_plugin_metadata
    @vite_plugin_metadata ||= begin
      command = vite_config_command
      if command
        stdout, _stderr, status = Timeout.timeout(10) do
          Open3.capture3(command, chdir: destination_root)
        end

        status.success? ? JSON.parse(stdout) : {}
      else
        {}
      end
    rescue JSON::ParserError, Timeout::Error
      {}
    end
  end

  def vite_config_command
    [
      CONFIG_BIN,
      "#{CONFIG_BIN}.cmd",
    ].find { |path| File.exist?(File.join(destination_root, path)) }
  end

  PLUGIN_OPENING = /reactEmailRails\s*\(\s*\{.*?/m

  def emails_path_from_vite_config
    source = vite_config_source
    return unless source

    first_capture(
      source,
      /#{PLUGIN_OPENING}emails:\s*["']([^"']+)["']/m,
      /#{PLUGIN_OPENING}emails:\s*\{.*?path:\s*["']([^"']+)["']/m,
    )
  end

  def extension_from_vite_config
    source = vite_config_source
    return unless source

    first_capture(
      source,
      /#{PLUGIN_OPENING}emails:\s*\{.*?extension:\s*["']([^"']+)["']/m,
      /#{PLUGIN_OPENING}emails:\s*\{.*?extension:\s*\[\s*["']([^"']+)["']/m,
    )
  end

  def first_capture(source, *patterns)
    patterns.each do |pattern|
      match = source[pattern, 1]
      return match if match
    end
    nil
  end

  def vite_config_source
    @vite_config_source ||= begin
      path = ReactEmailRails::Generators::VITE_CONFIG_FILES.find do |candidate|
        File.exist?(File.join(destination_root, candidate))
      end

      File.read(File.join(destination_root, path)) if path
    end
  end

  def extension_from_existing_email_components
    dominant_extension(Dir[File.join(destination_root, emails_path, "**/*.{tsx,jsx}")])
  end

  def extension_from_existing_app_components
    dominant_extension(Dir[File.join(destination_root, "app/javascript/**/*.{tsx,jsx}")])
  end

  def dominant_extension(paths)
    paths
      .map { |path| File.extname(path) }
      .select { |extension| [".tsx", ".jsx"].include?(extension) }
      .tally
      .max_by { |_extension, count| count }
      &.first
  end

  def extension_from_typescript_signal
    return ".tsx" if File.exist?(File.join(destination_root, "tsconfig.json"))

    package_path = File.join(destination_root, "package.json")
    return unless File.exist?(package_path)

    package = JSON.parse(File.read(package_path))
    dependencies = package.fetch("dependencies", {}).merge(package.fetch("devDependencies", {}))
    ".tsx" if dependencies.key?("typescript")
  rescue JSON::ParserError
    nil
  end

  def normalize_emails_path(path)
    path.to_s.delete_prefix("/").delete_suffix("/")
  end

  def normalize_extension(extension)
    extension = extension.to_s
    extension = ".#{extension}" unless extension.start_with?(".")

    unless extension.match?(/\A\.[a-zA-Z0-9_.-]+\z/)
      raise(Thor::Error, "Invalid React Email component extension: #{extension.inspect}")
    end

    extension
  end
end
