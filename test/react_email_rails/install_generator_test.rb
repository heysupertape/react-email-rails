require("test_helper")
require("fileutils")
require("rails/generators")
require("generators/react_email_rails/install_generator")

class ReactEmailRails::InstallGeneratorTest < Rails::Generators::TestCase
  tests(ReactEmailRails::Generators::InstallGenerator)
  destination(File.expand_path("../../tmp/install_generator", __dir__))

  setup(:prepare_destination)

  test("creates the initializer, Vite config, and email directory") do
    run_generator(["--skip-package-install"])

    assert_file("config/initializers/react_email_rails.rb", /configuration options/)
    assert_file("vite.config.ts", /reactEmailRails\(\)/)
    assert_directory("app/javascript/emails")
  end

  test("adds reactEmailRails to an existing Vite config") do
    write_destination_file(
      "vite.config.ts",
      <<~TS,
        import { defineConfig } from "vite"
        import react from "@vitejs/plugin-react"

        export default defineConfig({
          plugins: [react()],
        })
      TS
    )

    run_generator(["--skip-package-install"])

    assert_file("vite.config.ts", /import \{ reactEmailRails \} from "react-email-rails"/)
    assert_file("vite.config.ts", /plugins: \[reactEmailRails\(\), react\(\)\]/)
  end

  test("leaves existing JavaScript dependencies alone") do
    write_destination_file(
      "package.json",
      JSON.pretty_generate(
        "dependencies" => {
          "react-email-rails" => "^0.1.0",
          "@react-email/render" => "^2.0.0",
          "@react-email/components" => "^1.0.0",
          "react" => "^19.0.0",
          "react-dom" => "^19.0.0",
        },
        "packageManager" => "pnpm@10.34.1",
      ),
    )

    run_generator(["--skip-vite"])

    assert_file("package.json", /"react-email-rails"/)
  end

  private

  def write_destination_file(path, content)
    full_path = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end
end
