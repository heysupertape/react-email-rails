require_relative("lib/react_email_rails/version")

Gem::Specification.new do |spec|
  spec.name = "react-email-rails"
  spec.version = ReactEmailRails::VERSION
  spec.authors = ["Supertape"]
  spec.email = ["hi@supertape.com"]

  spec.summary = "Build and send emails using React and Rails"
  spec.description = "Seamless integration between Action Mailer and React Email components."
  spec.homepage = "https://github.com/heysupertape/react-email-rails"
  spec.license = "MIT"

  spec.metadata = {
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{spec.homepage}/blob/main/README.md",
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "rubygems_mfa_required" => "true",
  }

  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*", "README.md", "CHANGELOG.md", "CONTRIBUTING.md", "LICENSE.md", "SECURITY.md"] }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.3"

  spec.add_dependency("actionmailer", ">= 7.1", "< 9.0")
  spec.add_dependency("activesupport", ">= 7.1", "< 9.0")
  spec.add_dependency("railties", ">= 7.1", "< 9.0")

  spec.add_development_dependency("rubocop-minitest")
  spec.add_development_dependency("rubocop-performance")
  spec.add_development_dependency("rubocop-rails")
  spec.add_development_dependency("rubocop-shopify")
end
