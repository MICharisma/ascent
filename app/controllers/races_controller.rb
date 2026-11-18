class RacesController < ApplicationController
  before_action :set_race, only: %i[ show edit update destroy ]

  def index
    races_scope = Race.with_naming_details.includes(candidacies: :citizen).recent.visible_to(current_voter)
    races_scope = races_scope.where(office_id: params[:office_id]) if params[:office_id]
    races_scope = races_scope.where(election_id: params[:election_id]) if params[:election_id]
    elections = Election.where(id: races_scope.reorder(nil).select(:election_id))
    years = Year.where(id: elections.select(:year_id)).order(year: :desc).pluck(:year)
    kinds = elections.where.not(kind: [ nil, "" ]).distinct.order(:kind).pluck(:kind)

    races_scope = filtered(races_scope)
    status_counts = races_scope.except(:includes, :order).group(:status).count
    races_scope = races_scope.where(status: filters["status"]) if filters["status"].present?
    @pagy, @races = pagy(races_scope.order(id: :asc))
    render Views::Races::IndexView.new(races: @races, pagy: @pagy, filters: filters, scope: listing_scope,
      scope_record: scope_record, status_counts: status_counts, states: State.order(:name), years: years, kinds: kinds)
  end

  def show
    render Views::Races::ShowView.new(race: @race)
  end

  def new
    @race = Race.new(election_id: params[:election_id])
    render Views::Races::NewView.new(race: @race)
  end

  def edit
    render Views::Races::EditView.new(race: @race)
  end

  def create
    @race = Race.new(race_params)

    if @race.save
      redirect_to @race, notice: "Race was successfully created."
    else
      render Views::Races::NewView.new(race: @race), status: :unprocessable_entity
    end
  end

  def update
    if @race.update(race_params)
      redirect_to @race, notice: "Race was successfully updated.", status: :see_other
    else
      render Views::Races::EditView.new(race: @race), status: :unprocessable_entity
    end
  end

  def destroy
    @race.destroy!
    redirect_to races_url, notice: "Race was successfully destroyed.", status: :see_other
  end

  private

  def filters
    @filters ||= params.permit(:q, :state_id, :year, :status, :kind, :near).to_h
      .tap { it.delete("near") unless it["near"] == "1" && current_voter&.current_residences&.any? }
  end

  def listing_scope
    params.permit(:office_id, :election_id).to_h
  end

  # The office or election a list is narrowed to, named in its heading.
  def scope_record
    if params[:office_id] then Office.find(params[:office_id])
    elsif params[:election_id] then Election.find(params[:election_id])
    end
  end

  # Every filter but status, which the tabs count across.
  def filtered(races)
    races = races.matching(filters["q"]) if filters["q"].present?
    races = races.in_jurisdictions(current_voter.ballot_jurisdictions) if filters["near"]
    races = races.in_state(State.includes(:jurisdiction).find(filters["state_id"])) if filters["state_id"].present?
    races = races.where(elections: { year_id: Year.where(year: filters["year"]).select(:id) }) if filters["year"].present?
    races = races.where(elections: { kind: filters["kind"] }) if filters["kind"].present?
    races
  end

  def set_race
    @race = Race.with_naming_details.find(params[:id])
  end

  def race_params
    params.require(:race).permit(:election_id, :office_id, :status, :description)
  end
end
