module ReactEmailRails
  # `warnings` carries non-fatal renderer warnings (e.g. document nodes dropped
  # because no extension rendered them); empty for component renders.
  RenderedEmail = Data.define(:html, :text, :warnings) do
    def initialize(html:, text:, warnings: [])
      super
    end
  end
end
