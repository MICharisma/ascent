# frozen_string_literal: true

# A citizen's or policy's quality ratings. A signed-in voter sees a row for each quality they have rated,
# suggested qualities to rate next, and a picker listing every quality; a visitor is asked to sign in.
#   DimensionRatings(rated: @citizen)
class Views::Components::DimensionRatings < Views::ApplicationView
  prop :rated, ApplicationRecord

  def view_template
    section(class: "place-section dimension-ratings", id: dom_id(@rated, :dimension_ratings)) do
      section_heading("Your ratings", "Separate from your ballot")
      current_voter ? rating_rows : sign_in_prompt
    end
  end

  private

  def dimensions
    @rated.class.rating_dimensions
  end

  def rating_rows
    div(class: "dimension-rating-rows", data: { controller: "dimension-rating", dimension_rating_url_value: polymorphic_path([ @rated, :dimension_ratings ]),
      action: "dimension-suggestions:select->dimension-rating#openDimension" }) do
      precision_control
      dimensions.each { DimensionRatingRow(rated: @rated, dimension: it) }
      dimension_picker
    end
  end

  def precision_control
    div(class: "precision-control", role: "group", aria: { label: "Adjustment size for keyboard and drag" }) do
      precision_button "coarse", "Coarse", pressed: true
      precision_button "fine", "Fine", pressed: false
    end
  end

  def precision_button(precision, label, pressed:)
    button(type: "button", aria: { pressed: pressed.to_s },
      data: { precision: precision, dimension_rating_target: "precisionButton", action: "dimension-rating#changePrecision" }) { label }
  end

  def dimension_picker
    div(class: "dimension-picker", data: { controller: "dimension-suggestions",
      dimension_suggestions_url_value: polymorphic_path([ @rated, :dimension_rating_suggestions ]) }) do
      div(class: "dimension-suggestions", data: { dimension_suggestions_target: "suggestions" }) do
        DimensionSuggestions.new(voter: current_voter, rated: @rated).defaults.each { suggestion_button it }
      end
      button(type: "button", class: "dimension-suggest", data: { dimension_suggestions_target: "requestButton", action: "dimension-suggestions#suggest" }) { "Suggest for me" }
      p(class: "dimension-suggestions-status", role: "status", data: { dimension_suggestions_target: "status" })
      quality_select
    end
  end

  def suggestion_button(dimension)
    button(type: "button", data: { dimension_key: dimension.key, action: "dimension-suggestions#choose" }) { quality_name(dimension) }
  end

  def quality_select
    label(for: dom_id(@rated, :quality_picker), class: "dimension-select-label") { "Choose a quality" }
    select(id: dom_id(@rated, :quality_picker), class: "dimension-select", data: { action: "dimension-suggestions#choose" }) do
      option(value: "") { "Choose a quality" }
      dimensions.each { |dimension| option(value: dimension.key) { quality_name(dimension) } }
    end
  end

  def sign_in_prompt
    p(class: "card-text dimension-ratings-sign-in") do
      link_to "Sign in", new_voter_session_path, class: "text-link"
      plain " to rate this #{@rated.model_name.human.downcase} on #{dimensions.size} qualities."
    end
  end
end
