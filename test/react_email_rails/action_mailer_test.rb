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

class SharedPropsMailer < ApplicationMailer
  react_email_share(brand: "Acme")
  react_email_share(total: -> { compute_total })
  react_email_share do
    { action: action_name }
  end
  react_email_share(only: [:promo]) do
    { promo: true }
  end

  def show
    mail(react: { title: "Show" }, to: "a@example.com", subject: "Show")
  end

  def promo
    mail(react: { title: "Promo" }, to: "a@example.com", subject: "Promo")
  end

  def override
    mail(react: { brand: "Custom" }, to: "a@example.com", subject: "Override")
  end

  def bare
    mail(react: true, to: "a@example.com", subject: "Bare")
  end

  def explicit
    mail(react: "shared_props_mailer/show", props: { title: "Explicit" }, to: "a@example.com", subject: "Explicit")
  end

  def with_instance_share
    react_email_share(notice: "instance")
    mail(react: { title: "Instance" }, to: "a@example.com", subject: "Instance")
  end

  private

  def compute_total = 42
end

class ChildSharedPropsMailer < SharedPropsMailer
  react_email_share(scope: "child")

  def show
    mail(react: { title: "Child" }, to: "a@example.com", subject: "Child")
  end
end

class DeepMergeMailer < ApplicationMailer
  react_email_share do
    { settings: { theme: "light", locale: "en" } }
  end

  def shallow
    mail(react: { settings: { theme: "dark" } }, to: "a@example.com", subject: "Shallow")
  end

  def deep
    mail(react: { settings: { theme: "dark" } }, deep_merge: true, to: "a@example.com", subject: "Deep")
  end
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

    def initialize(payload:, label:, response: :email)
      @payload = payload
      @label = label
      @response = response
    end

    def render
      props = @payload[:props] || {}
      name = props[:name] || props["name"]
      self.class.requests << Request.new(payload: @payload, label: @label)
      ReactEmailRails::RenderedEmail.new(html: "<h1>Hello #{name}</h1>", text: "Hello #{name}")
    end
  end

  class FailingRenderer
    def initialize(payload:, label:, response: :email); end

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

class ReactEmailRails::SharedPropsTest < ActiveSupport::TestCase
  setup do
    ReactEmailRails::ActionMailerTest::FakeRenderer.requests = []
  end

  def props_for(&block)
    ReactEmailRails::ActionMailerTest::FakeRenderer.requests = []
    with_react_email_config(render_mode: ReactEmailRails::ActionMailerTest::FakeRenderer, &block)
    ReactEmailRails::ActionMailerTest::FakeRenderer.requests.sole.props
  end

  test("merges shared props beneath the per-mail props") do
    props = props_for { SharedPropsMailer.show.message }

    assert_equal({ "brand" => "Acme", "total" => 42, "action" => "show", "title" => "Show" }, props)
  end

  test("per-mail props win over shared props on conflict") do
    props = props_for { SharedPropsMailer.override.message }

    assert_equal("Custom", props["brand"])
  end

  test("blocks are evaluated lazily in the mailer instance context") do
    props = props_for { SharedPropsMailer.promo.message }

    assert_equal("promo", props["action"])
  end

  test("lambda values are evaluated lazily in the mailer instance context") do
    props = props_for { SharedPropsMailer.show.message }

    assert_equal(42, props["total"])
  end

  test("filters scope a shared block to specific actions") do
    assert(props_for { SharedPropsMailer.promo.message }["promo"])
    assert_nil(props_for { SharedPropsMailer.show.message }["promo"])
  end

  test("shared props apply to the explicit component and props form") do
    props = props_for { SharedPropsMailer.explicit.message }

    assert_equal({ "brand" => "Acme", "total" => 42, "action" => "explicit", "title" => "Explicit" }, props)
  end

  test("shared props apply to react: true with no instance props") do
    props = props_for { SharedPropsMailer.bare.message }

    assert_equal({ "brand" => "Acme", "total" => 42, "action" => "bare" }, props)
  end

  test("react_email_share inside an action shares props for that mail") do
    props = props_for { SharedPropsMailer.with_instance_share.message }

    assert_equal("instance", props["notice"])
    assert_equal("Instance", props["title"])
  end

  test("subclasses inherit shared props and can add their own") do
    props = props_for { ChildSharedPropsMailer.show.message }

    assert_equal({ "brand" => "Acme", "total" => 42, "action" => "show", "scope" => "child", "title" => "Child" }, props)
  end

  test("shallow merge replaces nested shared hashes by default") do
    props = props_for { DeepMergeMailer.shallow.message }

    assert_equal({ "theme" => "dark" }, props["settings"])
  end

  test("deep_merge: true merges nested shared hashes") do
    props = props_for { DeepMergeMailer.deep.message }

    assert_equal({ "theme" => "dark", "locale" => "en" }, props["settings"])
  end

  test("deep_merge_shared_props config deep merges without a per-mail flag") do
    props = with_react_email_config(
      render_mode: ReactEmailRails::ActionMailerTest::FakeRenderer,
      deep_merge_shared_props: true,
    ) do
      DeepMergeMailer.shallow.message
      ReactEmailRails::ActionMailerTest::FakeRenderer.requests.sole.props
    end

    assert_equal({ "theme" => "dark", "locale" => "en" }, props["settings"])
  end
end
