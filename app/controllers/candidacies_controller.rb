class CandidaciesController < ApplicationController
  before_action :set_candidacy, only: %i[ show edit update destroy ]

  def index
    candidacies_scope = Candidacy.includes(:citizen, :ballot_lines, race: [ :election, { office: [ :position, { jurisdiction: :jurisdictionable } ] } ])
      .visible_to(current_voter).joins(race: :election).order("elections.election_date DESC", :id)
    candidacies_scope = candidacies_scope.where(citizen_id: params[:citizen_id]) if params[:citizen_id]
    candidacies_scope = candidacies_scope.where(race_id: params[:race_id]) if params[:race_id]
    candidacies_scope = candidacies_scope.where(citizen_id: Citizen.named_like(filters["q"]).select(:id)) if filters["q"].present?
    candidacies_scope = candidacies_scope.where(status: filters["status"]) if filters["status"].present?
    @pagy, @candidacies = pagy(candidacies_scope)
    render Views::Candidacies::IndexView.new(candidacies: @candidacies, pagy: @pagy, filters: filters,
      scope: params.permit(:citizen_id, :race_id).to_h, rating_counts: Rating.where(candidacy: @candidacies).group(:candidacy_id).count)
  end

  def show
    render Views::Candidacies::ShowView.new(candidacy: @candidacy)
  end

  def new
    @candidacy = Candidacy.new
    render Views::Candidacies::NewView.new(candidacy: @candidacy)
  end

  def edit
    render Views::Candidacies::EditView.new(candidacy: @candidacy)
  end

  def create
    @candidacy = Candidacy.new(candidacy_params)

    if @candidacy.save
      redirect_to @candidacy, notice: "Candidacy was successfully created."
    else
      render Views::Candidacies::NewView.new(candidacy: @candidacy), status: :unprocessable_entity
    end
  end

  def update
    if @candidacy.update(candidacy_params)
      redirect_to @candidacy, notice: "Candidacy was successfully updated.", status: :see_other
    else
      render Views::Candidacies::EditView.new(candidacy: @candidacy), status: :unprocessable_entity
    end
  end

  def destroy
    @candidacy.destroy!
    redirect_to candidacies_url, notice: "Candidacy was successfully destroyed.", status: :see_other
  end

  private

  def filters
    @filters ||= params.permit(:q, :status).to_h
  end

  def set_candidacy
    @candidacy = Candidacy.includes(:citizen, :ballot_lines, primary_candidacy: { office: :nominating_organization }, race: [ :election, { office: [ :position, { jurisdiction: :jurisdictionable } ] } ]).find(params[:id])
  end

  def candidacy_params
    params.require(:candidacy).permit(:citizen_id, :race_id, :status, :announcement_date, :participation, :platform_summary,
      image_placements_attributes: [ :id, :image_id, :position, :_destroy, image_attributes: %i[id file url alt_text credit source_url] ])
  end
end
