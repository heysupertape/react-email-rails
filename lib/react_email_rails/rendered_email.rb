module ReactEmailRails
  # `warnings` are non-fatal (document nodes nothing rendered); empty for component renders.
  RenderedEmail = Data.define(:html, :text, :warnings) do
    def initialize(html:, text:, warnings: [])
      super
    end
  end
end
