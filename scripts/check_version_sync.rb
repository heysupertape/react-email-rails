#!/usr/bin/env ruby
require("json")
require_relative("../lib/react_email_rails/version")

root = File.expand_path("..", __dir__)
vite_package = JSON.parse(File.read(File.join(root, "vite/package.json")))

unless vite_package.fetch("version") == ReactEmailRails::VERSION
  abort("vite/package.json version #{vite_package.fetch("version").inspect} does not match ReactEmailRails::VERSION #{ReactEmailRails::VERSION.inspect}")
end

puts("Ruby gem and Vite package are in sync at #{ReactEmailRails::VERSION}")
