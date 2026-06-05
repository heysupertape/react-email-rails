require("json")
require_relative("vite_config_files")

module ReactEmailRails; end
module ReactEmailRails::Generators; end

class ReactEmailRails::Generators::InstallGenerator < Rails::Generators::Base
  JAVASCRIPT_PACKAGES = [
    "react-email-rails",
    "@react-email/render",
    "@react-email/components",
    "react",
    "react-dom",
  ].freeze

  PACKAGE_MANAGER_LOCKFILES = {
    "pnpm-lock.yaml" => "pnpm",
    "yarn.lock" => "yarn",
    "bun.lock" => "bun",
    "bun.lockb" => "bun",
    "package-lock.json" => "npm",
  }.freeze

  SUPPORTED_PACKAGE_MANAGERS = ["bun", "npm", "pnpm", "yarn"].freeze
  VITE_CONFIG_FILES = ReactEmailRails::Generators::VITE_CONFIG_FILES

  VITE_IMPORT = 'import { reactEmailRails } from "react-email-rails"'

  source_root(File.expand_path("templates", __dir__))

  class_option(
    :package_manager,
    type: :string,
    desc: "JavaScript package manager to use: npm, pnpm, yarn, or bun",
  )
  class_option(
    :skip_package_install,
    type: :boolean,
    default: false,
    desc: "Skip installing JavaScript dependencies",
  )
  class_option(
    :skip_vite,
    type: :boolean,
    default: false,
    desc: "Skip updating vite.config.*",
  )
  def copy_initializer
    template("initializer.rb", "config/initializers/react_email_rails.rb")
  end

  def install_javascript_dependencies
    return if options[:skip_package_install]

    package = package_json
    unless package
      say_status(:skip, "JavaScript dependencies; package.json was not found", :yellow)
      return
    end

    missing = missing_javascript_packages(package)
    if missing.empty?
      say_status(:identical, "JavaScript dependencies", :green)
      return
    end

    manager = package_manager(package)
    unless manager
      say_status(
        :skip,
        "JavaScript dependencies; could not detect npm, pnpm, yarn, or bun",
        :yellow,
      )
      return
    end

    run(javascript_install_command(manager, missing))
  end

  def configure_vite
    return if options[:skip_vite]

    if (config = vite_config_path)
      update_vite_config(config)
    else
      template("vite.config.ts", "vite.config.ts")
    end
  end

  def create_email_directory
    empty_directory("app/javascript/emails")
  end

  private

  def destination_path(path)
    File.join(destination_root, path)
  end

  def package_json_path
    destination_path("package.json")
  end

  def package_json
    return unless File.exist?(package_json_path)

    JSON.parse(File.read(package_json_path))
  rescue JSON::ParserError => e
    say_status(:skip, "JavaScript dependencies; package.json is invalid: #{e.message}", :yellow)
    nil
  end

  def missing_javascript_packages(package)
    dependencies = package.fetch("dependencies", {}).merge(package.fetch("devDependencies", {}))

    JAVASCRIPT_PACKAGES.reject { |name| dependencies.key?(name) }
  end

  def package_manager(package)
    manager = options[:package_manager].presence || package_manager_from_package_json(package) || package_manager_from_lockfile
    return unless manager

    manager = manager.to_s
    raise(Thor::Error, "Unsupported package manager: #{manager}") if SUPPORTED_PACKAGE_MANAGERS.exclude?(manager)

    manager
  end

  def package_manager_from_package_json(package)
    package.fetch("packageManager", "").to_s.split("@").first.presence
  end

  def package_manager_from_lockfile
    lockfile = PACKAGE_MANAGER_LOCKFILES.keys.find { |path| File.exist?(destination_path(path)) }
    PACKAGE_MANAGER_LOCKFILES[lockfile]
  end

  def javascript_install_command(manager, packages)
    case manager
    when "npm"
      "npm install #{packages.join(" ")}"
    when "pnpm"
      "pnpm add #{packages.join(" ")}"
    when "yarn"
      "yarn add #{packages.join(" ")}"
    when "bun"
      "bun add #{packages.join(" ")}"
    end
  end

  def vite_config_path
    VITE_CONFIG_FILES.find { |path| File.exist?(destination_path(path)) }
  end

  def update_vite_config(path)
    full_path = destination_path(path)
    source = File.read(full_path)

    if configured_for_react_email?(source)
      say_status(:identical, path, :green)
      return
    end

    updated = insert_react_email_plugin(source)
    unless updated
      say_status(:skip, "#{path}; add reactEmailRails() to the Vite plugins array", :yellow)
      return
    end

    File.write(full_path, ensure_react_email_import(updated))
    say_status(:insert, path, :green)
  end

  def configured_for_react_email?(source)
    source.match?(/reactEmailRails\s*\(/)
  end

  def insert_react_email_plugin(source)
    return source if configured_for_react_email?(source)

    if source.match?(/plugins:\s*\[\s*\]/)
      source.sub(/plugins:\s*\[\s*\]/, "plugins: [reactEmailRails()]")
    elsif source.match?(/plugins:\s*\[/)
      source.sub(/plugins:\s*\[/) { |match| "#{match}reactEmailRails(), " }
    elsif source.match?(/defineConfig\(\s*\{/)
      source.sub(/defineConfig\(\s*\{/) { |match| "#{match}\n  plugins: [reactEmailRails()]," }
    elsif source.match?(/export\s+default\s+\{/)
      source.sub(/export\s+default\s+\{/) { |match| "#{match}\n  plugins: [reactEmailRails()]," }
    end
  end

  def ensure_react_email_import(source)
    return source if source.match?(/from\s+["']react-email-rails["']/)

    lines = source.lines
    last_import_index = (lines.length - 1).downto(0).find { |index| lines[index].match?(/\Aimport\b/) }

    if last_import_index
      lines.insert(last_import_index + 1, "#{VITE_IMPORT}\n")
      lines.join
    else
      "#{VITE_IMPORT}\n\n#{source}"
    end
  end
end
