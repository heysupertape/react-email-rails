#!/usr/bin/env ruby
require("json")
require_relative("../lib/react_email_rails/version")
require_relative("../lib/react_email_rails/render_protocol")

root = File.expand_path("..", __dir__)
vite_package = JSON.parse(File.read(File.join(root, "vite/package.json")))
vite_version_source = File.read(File.join(root, "vite/src/version.ts"))

unless vite_package.fetch("version") == ReactEmailRails::VERSION
  abort("vite/package.json version #{vite_package.fetch("version").inspect} does not match ReactEmailRails::VERSION #{ReactEmailRails::VERSION.inspect}")
end

unless vite_version_source.match?(/VERSION = #{Regexp.escape(ReactEmailRails::VERSION.inspect)}/)
  abort("vite/src/version.ts VERSION does not match ReactEmailRails::VERSION #{ReactEmailRails::VERSION.inspect}")
end

unless vite_version_source.match?(/RENDER_PROTOCOL_VERSION = #{ReactEmailRails::RENDER_PROTOCOL_VERSION}\b/)
  abort("vite/src/version.ts RENDER_PROTOCOL_VERSION does not match ReactEmailRails::RENDER_PROTOCOL_VERSION #{ReactEmailRails::RENDER_PROTOCOL_VERSION}")
end

# Assert the bundle path matches on both sides so a one-sided edit fails here, not as
# "bundle not found" at render time. Regex-extracted to avoid heavy requires.
configuration_source = File.read(File.join(root, "lib/react_email_rails/configuration.rb"))
ruby_bundle_path = configuration_source[/BUNDLE_PATH = "([^"]+)"/, 1]
index_source = File.read(File.join(root, "vite/src/index.ts"))
vite_bundle_path = "#{index_source[/OUT_DIR = "([^"]+)"/, 1]}/#{index_source[/BUNDLE_FILE = "([^"]+)"/, 1]}"

unless ruby_bundle_path && vite_bundle_path == ruby_bundle_path
  abort("vite/src/index.ts bundle path #{vite_bundle_path.inspect} does not match ReactEmailRails::Configuration::BUNDLE_PATH #{ruby_bundle_path.inspect}")
end

puts(
  "Ruby gem and Vite package are in sync at #{ReactEmailRails::VERSION} " \
    "with render protocol #{ReactEmailRails::RENDER_PROTOCOL_VERSION}",
)
