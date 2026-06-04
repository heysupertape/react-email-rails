# Security Policy

Please report security issues privately by emailing hi@supertape.com.

Do not open a public GitHub issue for suspected vulnerabilities. Include the affected version, a minimal reproduction when possible, and any relevant deployment details.

## Rendering editor documents

`ReactEmailRails.compose` renders an `@react-email/editor` document (Tiptap/ProseMirror JSON) server-side. Treat that document as untrusted input: it is typically authored in a visual editor and stored, then rendered later. The renderer only dispatches to the extensions you register for that document type, and React Email escapes rendered output, but URL and asset sanitization inside your custom extensions (links, image sources, button hrefs) remains your application's responsibility. Validate or sanitize those values where you build extensions or transform the document.
