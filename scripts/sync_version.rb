#!/usr/bin/env ruby
require("json")
require_relative("../lib/react_email_rails/version")

root = File.expand_path("..", __dir__)
package_json_path = File.join(root, "vite/package.json")
package_json = JSON.parse(File.read(package_json_path))

package_json["version"] = ReactEmailRails::VERSION
File.write(package_json_path, "#{JSON.pretty_generate(package_json)}\n")

puts("Synced vite/package.json to #{ReactEmailRails::VERSION}")
