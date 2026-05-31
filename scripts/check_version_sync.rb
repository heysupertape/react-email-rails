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

puts(
  "Ruby gem and Vite package are in sync at #{ReactEmailRails::VERSION} " \
    "with render protocol #{ReactEmailRails::RENDER_PROTOCOL_VERSION}",
)
