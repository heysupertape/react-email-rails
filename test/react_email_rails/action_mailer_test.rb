require("test_helper")

class ReactEmailTestMailer < ApplicationMailer
  use_react_instance_props

  def welcome
    mail(react: { name: "Ada" }, to: "ada@example.com", subject: "Welcome")
  end

  def explicit
    mail(
      react: "react_email_test_mailer/welcome",
      props: { name: "Grace" },
      to: "grace@example.com",
      subject: "Explicit",
    )
  end

  def assigns
    @name = "Katherine"
    mail(react: true, to: "katherine@example.com", subject: "Assigns")
  end

  def assigns_with_params
    @name = "Grace"
    mail(react: true, to: "grace@example.com", subject: "Assigns with params")
  end

  def invalid
    mail(react: { name: "Ada" }, props: { other: "ignored" }, to: "ada@example.com", subject: "Invalid")
  end
end

class ReactEmailNoAssignsMailer < ApplicationMailer
  def assigns
    @name = "Ada"
    mail(react: true, to: "ada@example.com", subject: "Assigns")
  end
end

class ReactEmailTestMailerPreview < ActionMailer::Preview
  delegate(:welcome, to: ReactEmailTestMailer)
end

class ReactEmailRails::ActionMailerTest < ActiveSupport::TestCase
  class FakeRenderer
    Request = Data.define(:payload, :label) do
      def component = payload[:component]
      def props = payload[:props]
      def render_options = payload[:renderOptions]
    end

    class << self
      attr_accessor(:requests)
    end

    def initialize(payload:, label:)
      @payload = payload
      @label = label
    end

    def render
      props = @payload[:props] || {}
      name = props[:name] || props["name"]
      self.class.requests << Request.new(payload: @payload, label: @label)
      ReactEmailRails::RenderedEmail.new(html: "<h1>Hello #{name}</h1>", text: "Hello #{name}")
    end
  end

  class FailingRenderer
    def initialize(payload:, label:); end

    def render
      raise(ReactEmailRails::RenderError, "render process down")
    end
  end

  setup do
    FakeRenderer.requests = []
  end

  test("mail react hash infers component and uses hash as props") do
    message = with_react_email_config(render_mode: FakeRenderer) { ReactEmailTestMailer.welcome.message }

    assert_equal("Welcome", message.subject)
    assert_equal(["ada@example.com"], message.to)
    assert(message.multipart?)
    assert_includes(message.html_part.body.decoded, "<h1>Hello Ada</h1>")
    assert_includes(message.text_part.body.decoded, "Hello Ada")

    request = FakeRenderer.requests.sole
    assert_equal("react_email_test_mailer/welcome", request.component)
    assert_equal({ "name" => "Ada" }, request.props)
  end

  test("mail react string uses explicit component and top-level props") do
    with_react_email_config(render_mode: FakeRenderer) { ReactEmailTestMailer.explicit.message }

    request = FakeRenderer.requests.sole
    assert_equal("react_email_test_mailer/welcome", request.component)
    assert_equal({ "name" => "Grace" }, request.props)
  end

  test("mail react true uses instance props when enabled") do
    with_react_email_config(render_mode: FakeRenderer) { ReactEmailTestMailer.assigns.message }

    request = FakeRenderer.requests.sole
    assert_equal("react_email_test_mailer/assigns", request.component)
    assert_equal({ "name" => "Katherine" }, request.props)
  end

  test("react true excludes mailer params from instance props") do
    with_react_email_config(render_mode: FakeRenderer) do
      ReactEmailTestMailer.with(token: "secret").assigns_with_params.message
    end

    request = FakeRenderer.requests.sole
    assert_equal({ "name" => "Grace" }, request.props)
  end

  test("react true without use_react_instance_props infers the component and sends no props") do
    with_react_email_config(render_mode: FakeRenderer) { ReactEmailNoAssignsMailer.assigns.message }

    request = FakeRenderer.requests.sole
    assert_equal("react_email_no_assigns_mailer/assigns", request.component)
    assert_equal({}, request.props)
  end

  test("rejects props when react is already a prop hash") do
    error = assert_raises(ArgumentError) do
      with_react_email_config(render_mode: FakeRenderer) { ReactEmailTestMailer.invalid.message }
    end

    assert_equal("Parameter `props` is not allowed when passing a Hash to `react`", error.message)
  end

  test("works through Action Mailer previews") do
    message = with_react_email_config(render_mode: FakeRenderer) do
      ActionMailer::Preview.find("react_email_test_mailer").call("welcome")
    end

    assert_equal("Welcome", message.subject)
    assert_includes(message.html_part.body.decoded, "<h1>Hello Ada</h1>")
  end

  test("resolves render options in the mailer context") do
    with_react_email_config(render_mode: FakeRenderer, render_options: -> { { html: { pretty: action_name == "welcome" } } }) do
      ReactEmailTestMailer.welcome.message
    end

    assert_equal({ "html" => { "pretty" => true } }, FakeRenderer.requests.sole.render_options)
  end

  test("raises render process failures instead of falling back to Action Mailer templates") do
    error = assert_raises(ReactEmailRails::RenderError) do
      with_react_email_config(render_mode: FailingRenderer) { ReactEmailTestMailer.welcome.message }
    end

    assert_equal("render process down", error.message)
  end
end
