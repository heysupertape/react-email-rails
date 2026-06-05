module ReactEmailRails
  RENDER_PROTOCOL_VERSION = 3

  module RenderProtocol
    extend(self)

    def compatible_response?(body)
      body["ok"] == true && compatible_metadata?(body)
    end

    def compatible_metadata?(body)
      body["protocolVersion"] == RENDER_PROTOCOL_VERSION &&
        body["packageVersion"] == VERSION
    end

    def mismatch_message(body)
      "renderer version mismatch: expected react-email-rails #{VERSION} protocol #{RENDER_PROTOCOL_VERSION}, " \
        "got package #{body["packageVersion"].inspect} protocol #{body["protocolVersion"].inspect}"
    end
  end
end
