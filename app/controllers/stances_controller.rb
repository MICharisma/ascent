class StancesController < ApplicationController
  before_action :set_stance, only: %i[ show edit update destroy ]

  # GET /stances or /stances.json
  def index
    stances = Stance.includes(:stance_evidences, approach: :issue, candidacy: [ :citizen, { race: { office: :position } } ]).visible_to(current_voter)
      .joins(candidacy: :citizen).merge(Citizen.by_name).order(:id)
    stances = stances.where(candidacy_id: Candidacy.where(citizen_id: Citizen.named_like(filters["q"]).select(:id)).select(:id)) if filters["q"].present?
    stances = stances.where(priority_level: filters["priority_level"]) if filters["priority_level"].present?
    @pagy, @stances = pagy(stances)
    render Views::Stances::IndexView.new(stances: @stances, pagy: @pagy, filters: filters)
  end

  # GET /stances/1 or /stances/1.json
  def show
    render Views::Stances::ShowView.new(stance: @stance)
  end

  # GET /stances/new
  def new
    @stance = Stance.new
    render Views::Stances::NewView.new(stance: @stance)
  end

  # GET /stances/1/edit
  def edit
    render Views::Stances::EditView.new(stance: @stance)
  end

  # POST /stances or /stances.json
  def create
    @stance = Stance.new(stance_params)

    respond_to do |format|
      if @stance.save
        format.html { redirect_to @stance, notice: "Stance was successfully created." }
        format.json { render :show, status: :created, location: @stance }
      else
        format.html { render Views::Stances::NewView.new(stance: @stance), status: :unprocessable_entity }
        format.json { render json: @stance.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /stances/1 or /stances/1.json
  def update
    respond_to do |format|
      if @stance.update(stance_params)
        format.html { redirect_to @stance, notice: "Stance was successfully updated." }
        format.json { render :show, status: :ok, location: @stance }
      else
        format.html { render Views::Stances::EditView.new(stance: @stance), status: :unprocessable_entity }
        format.json { render json: @stance.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /stances/1 or /stances/1.json
  def destroy
    @stance.destroy!

    respond_to do |format|
      format.html { redirect_to stances_path, status: :see_other, notice: "Stance was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  def filters
    @filters ||= params.permit(:q, :priority_level).to_h
  end

    # Use callbacks to share common setup or constraints between actions.
    def set_stance
      @stance = Stance.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def stance_params
      params.expect(stance: [ :candidacy_id, :approach_id, :explanation, :priority_level, :evidence_links ])
    end
end
