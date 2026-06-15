module Changelog
  extend(self)

  def notes_for(text, version)
    match = text.match(/^## #{Regexp.escape(version)}\n\n(?<notes>.*?)(?=\n## |\z)/m)
    return [nil, :missing] unless match

    notes = match[:notes].strip
    return [notes, :empty] if notes.empty? || notes.match?(/\b(TODO|TBD)\b/i)

    [notes, :ok]
  end
end
