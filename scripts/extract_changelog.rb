#!/usr/bin/env ruby
require_relative("changelog")

version = ARGV.fetch(0) do
  abort("Usage: ruby scripts/extract_changelog.rb X.Y.Z")
end

changelog = File.read(File.expand_path("../CHANGELOG.md", __dir__))
notes, status = Changelog.notes_for(changelog, version)

case status
when :missing
  abort("CHANGELOG.md is missing a ## #{version} section")
when :empty
  abort("CHANGELOG.md section ## #{version} needs release notes before publishing")
end

puts(notes)
