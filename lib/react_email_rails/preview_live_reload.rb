class ReactEmailRails::PreviewLiveReload
  SCRIPT_TEMPLATE = %(<script type="module" src="%s/@vite/client"></script>)
  BODY_CLOSE = %r{</body>}i

  class << self
    def previewing_email(message)
      url = ReactEmailRails.configuration.resolve_live_reload_url
      return unless url

      part = html_part(message)
      return unless part

      part.body = inject(part.body.decoded, url)
    end

    private

    def html_part(message)
      return message.html_part if message.html_part
      return message if message.mime_type == "text/html"

      nil
    end

    def inject(html, url)
      snippet = format(SCRIPT_TEMPLATE, url)
      return html if html.include?(snippet)
      return "#{html}#{snippet}" unless BODY_CLOSE.match?(html)

      html.sub(BODY_CLOSE) { |tag| "#{snippet}#{tag}" }
    end
  end
end
