require("test_helper")

class ReactEmailRails::PreviewLiveReloadTest < ActiveSupport::TestCase
  CLIENT_TAG = %(<script type="module" src="http://localhost:5173/@vite/client"></script>)

  def multipart_message(html)
    Mail.new do
      html_part do
        content_type("text/html; charset=UTF-8")
        body(html)
      end
      text_part do
        content_type("text/plain; charset=UTF-8")
        body("plain text")
      end
    end
  end

  def html_only_message(html)
    Mail.new.tap do |message|
      message.content_type("text/html; charset=UTF-8")
      message.body(html)
    end
  end

  def preview(message)
    ReactEmailRails::PreviewLiveReload.previewing_email(message)
  end

  test("does not register the preview interceptor outside development") do
    # Runs in RAILS_ENV=test; the interceptor is development-only, so it must stay unregistered here.
    assert_not_includes(ActionMailer::Base.preview_interceptors, ReactEmailRails::PreviewLiveReload)
  end

  test("injects the vite client before the closing body tag") do
    message = multipart_message("<html><body><h1>Hi</h1></body></html>")

    preview(message)

    assert_equal("<html><body><h1>Hi</h1>#{CLIENT_TAG}</body></html>", message.html_part.body.decoded)
  end

  test("appends the vite client when there is no body tag") do
    message = multipart_message("<h1>Hi</h1>")

    preview(message)

    assert_equal("<h1>Hi</h1>#{CLIENT_TAG}", message.html_part.body.decoded)
  end

  test("injects into a single-part html message") do
    message = html_only_message("<html><body>Hi</body></html>")

    preview(message)

    assert_equal("<html><body>Hi#{CLIENT_TAG}</body></html>", message.body.decoded)
  end

  test("leaves the plain-text part untouched") do
    message = multipart_message("<html><body>Hi</body></html>")

    preview(message)

    assert_equal("plain text", message.text_part.body.decoded)
    assert_not_includes(message.text_part.body.decoded, "@vite/client")
  end

  test("does not inject twice when previewed repeatedly") do
    message = multipart_message("<html><body>Hi</body></html>")

    preview(message)
    preview(message)

    assert_equal(1, message.html_part.body.decoded.scan("@vite/client").length)
  end

  test("uses the configured dev server url") do
    message = multipart_message("<html><body>Hi</body></html>")

    with_react_email_config(live_reload_url: "http://localhost:6006") do
      ReactEmailRails::PreviewLiveReload.previewing_email(message)
    end

    assert_includes(message.html_part.body.decoded, %(src="http://localhost:6006/@vite/client"))
  end

  test("does nothing when the live reload url is falsy") do
    message = multipart_message("<html><body>Hi</body></html>")

    with_react_email_config(live_reload_url: nil) { ReactEmailRails::PreviewLiveReload.previewing_email(message) }

    assert_equal("<html><body>Hi</body></html>", message.html_part.body.decoded)
  end
end
