#!/usr/bin/env ruby
require("json")
require("rubygems")
require_relative("../lib/react_email_rails/version")
require_relative("changelog")

tag = ARGV.fetch(0) do
  abort("Usage: ruby scripts/check_release_tag.rb vX.Y.Z")
end

unless tag.match?(/\Av\d+\.\d+\.\d+\z/)
  abort("Release tag #{tag.inspect} must use the vX.Y.Z format")
end

version = tag.delete_prefix("v")
gem_version = ReactEmailRails::VERSION
package_json = JSON.parse(File.read(File.expand_path("../vite/package.json", __dir__)))
package_version = package_json.fetch("version")

unless gem_version == version
  abort("Release tag #{tag.inspect} does not match ReactEmailRails::VERSION #{gem_version.inspect}")
end

unless package_version == version
  abort("Release tag #{tag.inspect} does not match vite/package.json version #{package_version.inspect}")
end

changelog = File.read(File.expand_path("../CHANGELOG.md", __dir__))
case Changelog.notes_for(changelog, version).last
when :missing
  abort("CHANGELOG.md is missing a ## #{version} section")
when :empty
  abort("CHANGELOG.md section ## #{version} needs release notes before publishing")
end

if ENV["GITHUB_OUTPUT"]
  File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |output|
    output.puts("version=#{version}")
    output.puts("tag=#{tag}")
    output.puts("gem_path=react-email-rails-#{version}.gem")
    output.puts("npm_package=react-email-rails-#{version}.tgz")
  end
end

puts("Release tag #{tag} matches gem and npm package version #{version}")
