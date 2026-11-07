# frozen_string_literal: true

# A citizen's name with the surname carrying the weight; given and middle names stay light.
class Views::Components::CitizenName < Views::ApplicationView
  prop :citizen, Citizen

  def view_template
    given = [ @citizen.first_name, @citizen.middle_name ].compact_blank.join(" ")
    span(class: "candidate-given") { "#{given} " } if given.present?
    strong(class: "candidate-surname") { @citizen.last_name }
  end
end
