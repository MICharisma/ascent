# frozen_string_literal: true

# The signed-in voter's slider for one quality, with the voters' average. Drag across for coarse steps,
# then down for fine ones; keys, Rate neutral and Clear do the rest. A quality the voter hasn't rated
# stays closed until they open it from the picker.
#   DimensionRatingRow(rated: @citizen, dimension: Citizen.rating_dimensions.first)
class Views::Components::DimensionRatingRow < Views::ApplicationView
  prop :rated, ApplicationRecord
  prop :dimension, SharedRatings::Dimension
  prop :opened, _Boolean, default: false
  prop :saved, _Boolean, default: false

  def view_template
    div(id: row_id, class: "dimension-rating-row", hidden: !(rated? || @opened), style: "--rating-position: #{position_percent(shown_value)}%",
      data: { dimension_rating_target: "row", dimension: @dimension.to_h.to_json, rated: rated?.to_s, key: @dimension.key }) do
      row_header
      p(class: "dimension-rating-question") { @dimension.question }
      rating_track
      adjustment_help
      endpoints
      p(id: summary_id, class: "dimension-rating-summary") { summary }
      status_line
    end
  end

  # The controller targets its Turbo Stream with this before rendering, so it can't use the view helper.
  def row_id
    ActionView::RecordIdentifier.dom_id(@rated, "#{@dimension.key.split(".").last}_rating")
  end

  private

  def rating
    return @rating if defined?(@rating)

    @rating = current_voter.dimension_ratings.find_by(rated: @rated, dimension_key: @dimension.key)
  end

  def rated?
    rating.present?
  end

  def shown_value
    rating&.value || @dimension.neutral_value
  end

  def position_percent(value)
    @dimension.position(value) * 100
  end

  def input_id
    "#{row_id}_input"
  end

  def summary_id
    "#{row_id}_summary"
  end

  def hint_id
    "#{row_id}_hint"
  end

  def row_header
    div(class: "dimension-rating-header") do
      label(for: input_id, class: "dimension-rating-label") { quality_name(@dimension) }
      span(class: "dimension-rating-value") { rated? ? signed(rating.value) : "Not rated" }
    end
  end

  def rating_track
    div(class: "dimension-rating-track") do
      average_marker
      input(type: "range", id: input_id, class: "dimension-rating-input", min: @dimension.minimum, max: @dimension.maximum, step: 1,
        value: shown_value, aria: { describedby: "#{summary_id} #{hint_id}", valuetext: rated? ? signed(rating.value) : "Not rated" },
        data: { dimension_rating_target: "slider", action: slider_actions })
      div(class: "dimension-rating-handle-track") do
        span(class: "dimension-rating-handle", aria: { hidden: "true" }, data: { action: "pointerdown->dimension-rating#startDrag" })
      end
    end
  end

  def slider_actions
    "input->dimension-rating#preview change->dimension-rating#commit keydown->dimension-rating#adjustWithKeyboard " \
      "pointerdown->dimension-rating#startDrag lostpointercapture->dimension-rating#cancelDrag"
  end

  def average_marker
    return unless average

    div(class: "dimension-rating-average-track", aria: { hidden: "true" }) do
      span(class: "dimension-rating-average-marker", style: "left: #{position_percent(average.round)}%", title: "Voters average #{signed(average)}")
    end
  end

  def adjustment_help
    div(class: "dimension-rating-help") do
      span(id: hint_id, class: "precision-hint") { "Drag down for finer adjustments" }
      span(class: "drag-precision", role: "status", aria: { live: "polite" })
      if rated?
        button(type: "button", class: "dimension-rating-clear", data: { action: "dimension-rating#clear" }) { "Clear" }
      else
        button(type: "button", class: "dimension-rating-neutral", data: { action: "dimension-rating#rateNeutral" }) { "Rate neutral" }
      end
    end
  end

  def endpoints
    div(class: "dimension-rating-endpoints") do
      span { @dimension.low_label }
      span { @dimension.high_label }
    end
  end

  def summary
    return "No voter has rated this yet" unless average

    "Voters average #{signed(average)} · #{pluralize(count, "rating")}"
  end

  def count
    voters_average.first
  end

  def average
    voters_average.last&.to_f
  end

  def voters_average
    @voters_average ||= @rated.voters_average_on(@dimension)
  end

  def status_line
    div(class: "dimension-rating-status", role: "status", aria: { live: "polite" }) do
      span(class: "status-indicator") { @saved ? "Saved" : "" }
      button(type: "button", class: "dimension-rating-retry", hidden: true, data: { action: "dimension-rating#retry" }) { "Retry" }
    end
  end

  def signed(value)
    number = value.round
    "#{"+" if number.positive?}#{ActiveSupport::NumberHelper.number_to_delimited(number)}"
  end
end
