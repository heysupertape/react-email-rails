require("json")
require("test_helper")

class ReactEmailRails::VersionSyncTest < ActiveSupport::TestCase
  test("Vite package version matches the Ruby gem version") do
    root = File.expand_path("../..", __dir__)
    vite_package = JSON.parse(File.read(File.join(root, "vite/package.json")))

    assert_equal(ReactEmailRails::VERSION, vite_package.fetch("version"))
  end
end
