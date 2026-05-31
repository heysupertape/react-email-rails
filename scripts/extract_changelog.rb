#!/usr/bin/env ruby
version = ARGV.fetch(0) do
  abort("Usage: ruby scripts/extract_changelog.rb X.Y.Z")
end

changelog = File.read(File.expand_path("../CHANGELOG.md", __dir__))
match = changelog.match(/^## #{Regexp.escape(version)}\n\n(?<notes>.*?)(?=\n## |\z)/m)

unless match
  abort("CHANGELOG.md is missing a ## #{version} section")
end

notes = match[:notes].strip
if notes.empty? || notes.match?(/\b(TODO|TBD)\b/i)
  abort("CHANGELOG.md section ## #{version} needs release notes before publishing")
end

puts(notes)
