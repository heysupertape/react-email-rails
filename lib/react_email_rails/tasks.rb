require("fileutils")

module ReactEmailRails::Tasks
  class << self
    def build
      command = build_command
      raise("react-email-rails build command not found at #{command.last.inspect}; run JavaScript package install first") unless File.exist?(command.last)

      system(*command, exception: true, chdir: Rails.root.to_s)
      raise("react-email-rails build completed, but the email bundle was not found at #{bundle_path.inspect}") unless File.file?(bundle_path)
    end

    def clobber
      FileUtils.rm_rf(Rails.root.join(File.dirname(ReactEmailRails::Configuration::BUNDLE_PATH)))
    end

    def verify
      return if ReactEmailRails.healthy?

      command = ReactEmailRails.configuration.send(:resolved_render_command)
      raise("react-email-rails renderer verification failed for command: #{command.inspect}")
    end

    private

    def build_command
      [
        ReactEmailRails.configuration.js_runtime,
        Rails.root.join(ReactEmailRails::Configuration::BUILD_SCRIPT).to_s,
      ]
    end

    def bundle_path
      Rails.root.join(ReactEmailRails::Configuration::BUNDLE_PATH).to_s
    end
  end
end
