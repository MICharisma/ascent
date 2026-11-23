require "insta/rspec"

# bin/insta, which reviews and accepts snapshots, sets the same path.
Insta.configure { |config| config.snapshot_path = "spec/snapshots" }

# Turns a rendered page into an outline of what a visitor can read and do: the
# headings, text, links, controls, and the regions that group them, in page
# order. Snapshot the outline with `match_snapshot(name, serializer: :interface)`
# to record each permutation of a page (role, settings, empty states) in one
# reviewable file. Styling and markup structure are left out, so restyling
# a page doesn't change its snapshots.
class InterfaceOutline < Insta::Serializers::Base
  REGIONS = %w[header nav main section article aside footer form fieldset details dialog ol ul table].freeze
  SKIPPED = %w[script style template noscript svg].freeze
  TEXT_BLOCKS = %w[p li dt dd td th figcaption legend caption blockquote].freeze
  RECORD_ID = %r{/(\d+|\h{8}-\h{4}-\h{4}-\h{4}-\h{12})(?=[/?#]|\z)}
  UUID = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/

  def self.serialize(html)
    document = Nokogiri::HTML(html)
    new.lines(document.at("main") || document.at("body")).join("\n") + "\n"
  end

  def lines(node, depth = 0)
    node.children.flat_map do |child|
      next outline(child, depth) if child.element?

      text = squish(child.text) if child.text?
      text.present? ? [ "#{"  " * depth}- text #{quote_text text}" ] : []
    end
  end

  private

  def outline(node, depth)
    return [] if SKIPPED.include?(node.name) || node["hidden"] || node["aria-hidden"] == "true"
    return [] if node.name == "dialog" && !node.has_attribute?("open")
    # A label's text already names its field, so only fields inside it remain.
    return node.element_children.flat_map { |child| outline(child, depth) } if node.name == "label"

    entry = describe(node)
    return lines(node, depth) unless entry

    children = REGIONS.include?(node.name) ? lines(node, depth + 1) : []
    [ "#{"  " * depth}- #{entry}#{":" if children.any?}" ] + children
  end

  def describe(node)
    case node.name
    when /\Ah([1-6])\z/ then "heading #{quote node} [level=#{$1}]"
    when "a" then "link #{quote node} → #{path node["href"]}"
    when "button" then "button #{quote node}#{flags node}"
    when "input" then input(node)
    when "select" then "combobox #{label node}#{flags node} = #{quote_text node.at("option[selected]")&.text.to_s}"
    when "textarea" then "textbox #{label node} [multiline]#{flags node}"
    when "img" then "img #{quote_text node["alt"].to_s}"
    when "summary" then "summary #{quote node}"
    when "progress" then "progressbar #{label node} #{node["value"]}/#{node["max"]}"
    when *REGIONS then region(node)
    when *TEXT_BLOCKS then text_block(node)
    end
  end

  def input(node)
    case node["type"]
    when "hidden" then nil
    when "submit", "button" then "button #{quote_text node["value"].to_s}#{flags node}"
    when "checkbox", "radio" then "#{node["type"]} #{label node}#{flags node}"
    else "textbox #{label node}#{flags node}#{" = #{quote_text node["value"]}" if node["value"].present?}"
    end
  end

  def region(node)
    name = node["aria-label"] || node.at_xpath("./legend | ./caption")&.text
    role = { "ol" => "list", "ul" => "list", "section" => "region", "details" => "group", "fieldset" => "group" }.fetch(node.name, node.name)
    return unless name || %w[form nav header footer dialog details].include?(node.name) || (role == "list" && node.element_children.any?)

    [ role, (quote_text(name) if name), (node["open"] ? "[open]" : nil) ].compact.join(" ")
  end

  # A text block becomes one line when it holds only text and inline styling;
  # otherwise its children are outlined in its place.
  def text_block(node)
    return if node.css("a, button, input, select, textarea, img, " + TEXT_BLOCKS.join(", ")).any?

    text = visible_text(node)
    "text #{quote_text text}" if text.present?
  end

  # Separate inline pieces with spaces, as a reader would hear them.
  def visible_text(node)
    node.xpath(".//text()[not(ancestor::*[@aria-hidden='true'])]").map { |piece| squish(piece.text) }.reject(&:empty?).join(" ")
  end

  def label(node)
    text = node["aria-label"] || (node["id"] && node.document.at("label[for='#{node["id"]}']")&.text) || node.ancestors("label").first&.text || node["placeholder"] || node["name"]
    quote_text text.to_s
  end

  def flags(node)
    found = %w[disabled required checked].select { |flag| node.has_attribute?(flag) }
    found << "current" if node["aria-current"].present?
    found.any? ? " [#{found.join(", ")}]" : ""
  end

  def path(href)
    href.to_s.sub(%r{\Ahttps?://[^/]+}, "").gsub(RECORD_ID, "/:id")
  end

  def quote(node) = quote_text(node["aria-label"].presence || visible_text(node))
  def quote_text(text) = squish(text).gsub(UUID, ":uuid").inspect
  def squish(text) = text.to_s.gsub(/\s+/, " ").strip
end

Insta::Serializers.register :interface, InterfaceOutline
