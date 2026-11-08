# frozen_string_literal: true

# A citizen's name with the family name carrying the weight; the other pieces
# stay light. The pieces come from Rizz when the integration is on
# (Citizen#display_name_parts). A name whose structure Rizz doesn't know is
# shown whole rather than guessing which part is the family name.
class Views::Components::CitizenName < Views::ApplicationView
  prop :citizen, Citizen

  def view_template
    parts = @citizen.display_name_parts
    return plain(@citizen.display_name) unless parts

    NameParts.runs(parts).each do |family, pieces|
      text = NameParts.text(pieces)
      family ? strong(class: "candidate-surname") { text } : span(class: "candidate-given") { text }
    end
  end
end
