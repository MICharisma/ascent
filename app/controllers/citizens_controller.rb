class CitizensController < ApplicationController
  before_action :set_citizen, only: %i[ show edit update destroy ]

  def index
    citizens_scope = Citizen.with_names.includes(candidacies: [ :ballot_lines, { race: [ :election, { office: [ :position, { jurisdiction: :jurisdictionable } ] } ] } ])
      .visible_to(current_voter).by_name
    citizens_scope = citizens_scope.named_like(filters["q"]) if filters["q"].present?
    citizens_scope = citizens_scope.ran_in(Race.in_state(State.includes(:jurisdiction).find(filters["state_id"]))) if filters["state_id"].present?
    @pagy, @citizens = pagy(citizens_scope)
    render Views::Citizens::IndexView.new(citizens: @citizens, pagy: @pagy, filters: filters, states: State.order(:name))
  end

  def show
    render Views::Citizens::ShowView.new(citizen: @citizen)
  end

  def new
    @citizen = Citizen.new
    render Views::Citizens::NewView.new(citizen: @citizen)
  end

  def edit
    render Views::Citizens::EditView.new(citizen: @citizen)
  end

  def create
    @citizen = Citizen.new(citizen_params)

    if @citizen.save
      redirect_to @citizen, notice: "Citizen was successfully created."
    else
      render Views::Citizens::NewView.new(citizen: @citizen), status: :unprocessable_entity
    end
  end

  def update
    if @citizen.update(citizen_params)
      redirect_to @citizen, notice: "Citizen was successfully updated.", status: :see_other
    else
      render Views::Citizens::EditView.new(citizen: @citizen), status: :unprocessable_entity
    end
  end

  def destroy
    @citizen.destroy!
    redirect_to citizens_url, notice: "Citizen was successfully destroyed.", status: :see_other
  end

  private

  def filters
    @filters ||= params.permit(:q, :state_id).to_h
  end

  def set_citizen
    @citizen = Citizen.with_candidacy_details.find(params[:id])
  end

  def citizen_params
    params.require(:citizen).permit(:first_name, :last_name, :middle_name, :email, :birth_date, :bio,
      image_placements_attributes: [ :id, :image_id, :position, :_destroy, image_attributes: %i[id file url alt_text credit source_url] ])
  end
end
