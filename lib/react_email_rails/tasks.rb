require("fileutils")

module ReactEmailRails::Tasks
  class << self
    def build
      command = build_command
      raise("react-email-rails build command not found at #{command.inspect}; run JavaScript package install first") unless File.exist?(command)

      system(command, exception: true, chdir: Rails.root.to_s)
      raise("react-email-rails build completed, but the email bundle was not found at #{bundle_path.inspect}") unless File.file?(bundle_path)
    end

    def clobber
      FileUtils.rm_rf(Rails.root.join(File.dirname(ReactEmailRails::Configuration::BUNDLE_PATH)))
    end

    private

    def build_command
      candidates = [
        ReactEmailRails::Configuration::BUILD_BIN,
        "#{ReactEmailRails::Configuration::BUILD_BIN}.cmd",
      ]
      candidates.map { |path| Rails.root.join(path).to_s }.find { |path| File.exist?(path) } ||
        Rails.root.join(ReactEmailRails::Configuration::BUILD_BIN).to_s
    end

    def bundle_path
      Rails.root.join(ReactEmailRails::Configuration::BUNDLE_PATH).to_s
    end
  end
end
