# frozen_string_literal: true

class Views::Mountains::CandidateColumn < Views::Components::Base
  def initialize(candidacy:, rating_value:, has_rating:, is_approved:, left_edge:, editable: false, rating_input_id: nil)
    @candidacy = candidacy
    @rating_value = rating_value
    @has_rating = has_rating
    @is_approved = is_approved
    @editable = editable
    @rating_input_id = rating_input_id
    @left_edge = left_edge
  end

  def view_template
    div(class: column_classes, data: column_data) do
      div(class: "rating-area", data: rating_area_data) do
        peak
        peak(left_edge: true) if @left_edge
        render Views::Mountains::RatingDot.new(
          rating_value: @rating_value,
          has_rating: @has_rating,
          is_approved: @is_approved
        )
      end

      div(class: "candidate-info") do
        h4(class: "column-name") do
          link_to @candidacy.citizen.name, @candidacy, class: "candidate-link"
        end
        Views::Mountains::PartyEndorsements(candidacy: @candidacy)

        p(
          class: "rating-value",
          data: { role: "rating-value" },
          hidden: !@has_rating
        ) { "Rating: #{@rating_value}" }
        if @candidacy.stances.any?
          p(class: "stance-count") do
            link_to "#{@candidacy.stances.count} policy positions", @candidacy, class: "stance-link"
          end
        end
      end
    end
  end

  def peak(left_edge: false)
    classes = left_edge ? "mountain-peak mountain-left-edge" : "mountain-peak"
    svg(class: classes, viewbox: "0 0 100 500", preserveaspectratio: "none", aria: { hidden: true }) do |s|
      s.path(class: "peak-body", data: { role: "peak-body" })
      s.path(class: "peak-summit", data: { role: "peak-summit" })
      s.path(class: "peak-ridge", data: { role: "peak-ridge" })
      s.path(class: "peak-rope", data: { role: "peak-rope" })
    end
  end

  def column_classes
    [ "candidate-column", ("off-ballot" if @candidacy.primary_candidacy_id.present?) ].compact.join(" ")
  end

  def column_data
    shared = { mountain_range_target: "column", rating: (@rating_value if @has_rating) }
    return shared unless @editable

    shared.merge(candidacy_id: @candidacy.id, rating_input_id: @rating_input_id)
  end

  def rating_area_data
    return {} unless @editable

    {
      role: "rating-area",
      action: "pointerdown->mountain-editor#startRatingDrag"
    }
  end
end
