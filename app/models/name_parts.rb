# Reading a name's pieces, as Rizz serves them in display_parts: an ordered
# list of hashes, each with its text and, for a name piece, a role (given,
# middle, family, suffix, nickname or other). Pieces without a role are
# separators: spaces and punctuation. The pieces join back into the name.
module NameParts
  module_function

  # Consecutive pieces grouped by whether they belong to the family name, as
  # [family?, pieces] pairs. A separator between two family pieces, as in
  # "García Márquez", stays in the family name.
  def runs(parts)
    family = parts.each_index.map do |index|
      next true if parts[index]["role"] == "family"
      next false if parts[index].key?("role")
      before = parts[0...index].reverse.find { it.key?("role") }
      after = parts[(index + 1)..].find { it.key?("role") }
      before&.dig("role") == "family" && after&.dig("role") == "family"
    end
    parts.zip(family).chunk_while { |(_, a), (_, b)| a == b }.map { |run| [ run.first.last, run.map(&:first) ] }
  end

  # The family name as written in the name, or nil when it has none (a
  # mononym).
  def family(parts)
    names = runs(parts).select(&:first).map { |_, pieces| text(pieces) }
    names.join(" ").presence
  end

  # The keys a name sorts by: the family name, then the other name pieces in
  # order. A name without a family name sorts by the whole name.
  def sort_keys(parts)
    surname = family(parts)
    return [ text(parts), "" ] unless surname
    [ surname, parts.select { it.key?("role") && it["role"] != "family" }.map { it["text"] }.join(" ") ]
  end

  def text(pieces)
    pieces.sum("") { it["text"] }
  end
end
