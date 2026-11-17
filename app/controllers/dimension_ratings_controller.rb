# Saves and clears the signed-in voter's own rating of one quality, answering with the redrawn row.
class DimensionRatingsController < ApplicationController
  def create
    rating = current_voter.dimension_ratings.find_or_initialize_by rated: rated, dimension_key: rating_params[:dimension_key]
    rating.value = rating_params[:value]
    return head :unprocessable_content unless rating.save

    respond_with_row rating.dimension, saved: true
  end

  def destroy
    rating = current_voter.dimension_ratings.find_by! rated: rated, dimension_key: rating_params[:dimension_key]
    rating.destroy!
    respond_with_row rating.dimension
  end

  private

  def rated
    @rated ||= params[:citizen_id] ? Citizen.find(params[:citizen_id]) : Policy.find(params[:policy_id])
  end

  def rating_params
    params.expect dimension_rating: %i[dimension_key value]
  end

  def respond_with_row(dimension, saved: false)
    row = Views::Components::DimensionRatingRow.new(rated: rated, dimension: dimension, opened: true, saved: saved)
    render turbo_stream: turbo_stream.replace(row.row_id, row)
  end
end
