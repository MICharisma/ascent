class RatingsController < ApplicationController
  before_action :set_rating, only: %i[ show edit update destroy ]

  def index
    @pagy, @ratings = pagy(Rating.includes(:voter, candidacy: [ :citizen, { race: { office: [ :position, { jurisdiction: :jurisdictionable } ] } } ]).order(created_at: :desc))
    render Views::Ratings::IndexView.new(ratings: @ratings, pagy: @pagy)
  end

  def show
    render Views::Ratings::ShowView.new(rating: @rating)
  end

  def new
    @rating = Rating.new
    render Views::Ratings::NewView.new(rating: @rating)
  end

  def edit
    render Views::Ratings::EditView.new(rating: @rating)
  end

  def create
    @rating = Rating.new(rating_params)

    if @rating.save
      redirect_to @rating, notice: "Rating was successfully created."
    else
      render Views::Ratings::NewView.new(rating: @rating), status: :unprocessable_entity
    end
  end

  def update
    if @rating.update(rating_params)
      redirect_to @rating, notice: "Rating was successfully updated.", status: :see_other
    else
      render Views::Ratings::EditView.new(rating: @rating), status: :unprocessable_entity
    end
  end

  def destroy
    @rating.destroy!
    redirect_to ratings_url, notice: "Rating was successfully destroyed.", status: :see_other
  end

  private

  def set_rating
    @rating = Rating.find(params[:id])
  end

  def rating_params
    params.require(:rating).permit(:rating)
  end
end
