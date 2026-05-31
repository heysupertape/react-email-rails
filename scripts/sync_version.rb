#!/usr/bin/env ruby
require("json")
require_relative("../lib/react_email_rails/version")
require_relative("../lib/react_email_rails/render_protocol")

root = File.expand_path("..", __dir__)
package_json_path = File.join(root, "vite/package.json")
package_json = JSON.parse(File.read(package_json_path))
vite_version_path = File.join(root, "vite/src/version.ts")

package_json["version"] = ReactEmailRails::VERSION
File.write(package_json_path, "#{JSON.pretty_generate(package_json)}\n")

vite_version = File.read(vite_version_path)
vite_version.sub!(/VERSION = "[^"]+"/, "VERSION = #{ReactEmailRails::VERSION.inspect}")
vite_version.sub!(/RENDER_PROTOCOL_VERSION = \d+/, "RENDER_PROTOCOL_VERSION = #{ReactEmailRails::RENDER_PROTOCOL_VERSION}")
File.write(vite_version_path, vite_version)

puts(
  "Synced Vite package version to #{ReactEmailRails::VERSION} " \
    "and render protocol to #{ReactEmailRails::RENDER_PROTOCOL_VERSION}",
)
