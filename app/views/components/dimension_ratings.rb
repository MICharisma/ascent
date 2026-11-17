# frozen_string_literal: true

# A citizen's or policy's quality ratings. A signed-in voter sees a row for each quality they have rated,
# and a button to open each one they haven't; a visitor is asked to sign in.
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
    div(class: "dimension-rating-rows", data: { controller: "dimension-rating", dimension_rating_url_value: polymorphic_path([ @rated, :dimension_ratings ]) }) do
      precision_control
      dimensions.each { DimensionRatingRow(rated: @rated, dimension: it) }
      dimension_picker if unrated_dimensions.any?
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
    div(class: "dimension-picker", data: { dimension_rating_target: "picker" }) do
      span(class: "dimension-picker-label") { "Rate" }
      unrated_dimensions.each do |dimension|
        button(type: "button", data: { dimension_key: dimension.key, action: "dimension-rating#openDimension" }) { quality_name(dimension) }
      end
    end
  end

  def unrated_dimensions
    @unrated_dimensions ||= dimensions.reject { rated_keys.include? it.key }
  end

  def rated_keys
    current_voter.dimension_ratings.where(rated: @rated).pluck(:dimension_key)
  end

  def sign_in_prompt
    p(class: "card-text dimension-ratings-sign-in") do
      link_to "Sign in", new_voter_session_path, class: "text-link"
      plain " to rate this #{@rated.model_name.human.downcase} on #{dimensions.size} qualities."
    end
  end
end
