#!/usr/bin/env ruby
require("rubygems")

USAGE = "Usage: ruby scripts/prepare_release.rb patch|minor|major|X.Y.Z"

bump = ARGV.fetch(0) do
  abort(USAGE)
end

root = File.expand_path("..", __dir__)
version_path = File.join(root, "lib/react_email_rails/version.rb")
version_source = File.read(version_path)
current = version_source[/VERSION = "(\d+\.\d+\.\d+)"/, 1]

abort("Could not find ReactEmailRails::VERSION in #{version_path}") unless current

major, minor, patch = current.split(".").map(&:to_i)
target =
  case bump
  when "patch"
    [major, minor, patch + 1].join(".")
  when "minor"
    [major, minor + 1, 0].join(".")
  when "major"
    [major + 1, 0, 0].join(".")
  when /\A\d+\.\d+\.\d+\z/
    bump
  else
    abort(USAGE)
  end

if Gem::Version.new(target) <= Gem::Version.new(current)
  abort("Target version #{target} must be greater than current version #{current}")
end

updated_source = version_source.sub(/VERSION = "\d+\.\d+\.\d+"/, "VERSION = #{target.inspect}")
File.write(version_path, updated_source)

system("ruby", File.join(root, "scripts/sync_version.rb"), exception: true)

changelog_path = File.join(root, "CHANGELOG.md")
changelog = File.read(changelog_path)
unless changelog.match?(/^## #{Regexp.escape(target)}$/)
  changelog.sub!(/^# Changelog\n\n/, "# Changelog\n\n## #{target}\n\n- TODO: Describe changes.\n\n")
  File.write(changelog_path, changelog)
end

puts("Prepared release #{target}")
puts("Next: replace the CHANGELOG.md TODO entry, run checks, commit, merge to main, and tag v#{target}.")
