module ReactEmailRails
  RenderedEmail = Data.define(:html, :text, :warnings) do
    def initialize(html:, text:, warnings: [])
      super
    end
  end
end
