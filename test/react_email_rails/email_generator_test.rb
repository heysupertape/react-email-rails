require("test_helper")
require("fileutils")
require("rails/generators")
require("generators/react_email_rails/email_generator")

class ReactEmailRails::EmailGeneratorTest < Rails::Generators::TestCase
  tests(ReactEmailRails::Generators::EmailGenerator)
  destination(File.expand_path("../../tmp/email_generator", __dir__))

  setup(:prepare_destination)

  test("creates a React Email mailer with components, test, and preview") do
    run_generator(["account", "created", "invited"])

    assert_file("app/mailers/account_mailer.rb", /class AccountMailer < ApplicationMailer/)
    assert_file("app/mailers/account_mailer.rb", /def created/)
    assert_file("app/mailers/account_mailer.rb", /mail to: "to@example.org", react: true/)
    assert_file("app/javascript/emails/account_mailer/created.tsx", /export default function Created/)
    assert_file("app/javascript/emails/account_mailer/invited.tsx", /AccountMailer#invited/)
    assert_file("test/mailers/account_mailer_test.rb", /ReactEmailRails.stub\(:render/)
    assert_file("test/mailers/previews/account_mailer_preview.rb", /AccountMailer.created/)
  end

  test("strips a mailer suffix like the Rails mailer generator") do
    run_generator(["account_mailer", "created"])

    assert_file("app/mailers/account_mailer.rb", /class AccountMailer < ApplicationMailer/)
    assert_file("app/javascript/emails/account_mailer/created.tsx", /AccountMailer#created/)
  end

  test("supports namespaced mailers") do
    run_generator(["admin/account", "created"])

    assert_file("app/mailers/admin/account_mailer.rb", /class Admin::AccountMailer < ApplicationMailer/)
    assert_file("app/javascript/emails/admin/account_mailer/created.tsx", /Admin::AccountMailer#created/)
    assert_file("test/mailers/admin/account_mailer_test.rb", /Admin::AccountMailer.created/)
    assert_file("test/mailers/previews/admin/account_mailer_preview.rb", /Admin::AccountMailerPreview/)
  end

  test("uses the React Email path and extension configured in Vite") do
    write_destination_file(
      "vite.config.ts",
      <<~TS,
        import { defineConfig } from "vite"
        import { reactEmailRails } from "react-email-rails"

        export default defineConfig({
          plugins: [
            reactEmailRails({
              emails: {
                path: "app/frontend/emails",
                extension: "jsx",
              },
            }),
          ],
        })
      TS
    )

    run_generator(["account", "created", "--skip-test", "--skip-preview"])

    assert_file("app/frontend/emails/account_mailer/created.jsx", /export default function Created/)
    assert_no_file("app/javascript/emails/account_mailer/created.tsx")
  end

  test("loads without requiring the main gem entrypoint first") do
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "-Ilib",
      "-e",
      'require "rails/generators"; require "generators/react_email_rails/email_generator"; puts ReactEmailRails::Generators::EmailGenerator::CONFIG_BIN',
      chdir: File.expand_path("../..", __dir__),
    )

    assert(status.success?, stderr)
    assert_equal("node_modules/.bin/react-email-rails-config", stdout.strip)
  end

  test("allows explicitly overriding the component path and extension") do
    run_generator(
      [
        "account",
        "created",
        "--emails-path=app/emails",
        "--extension=email.tsx",
        "--skip-test",
        "--skip-preview",
      ],
    )

    assert_file("app/emails/account_mailer/created.email.tsx", /AccountMailer#created/)
  end

  test("can skip tests and previews") do
    run_generator(["account", "created", "--skip-test", "--skip-preview"])

    assert_file("app/mailers/account_mailer.rb")
    assert_no_file("test/mailers/account_mailer_test.rb")
    assert_no_file("test/mailers/previews/account_mailer_preview.rb")
  end
end
