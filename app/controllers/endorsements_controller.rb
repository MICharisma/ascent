class EndorsementsController < ApplicationController
  def index
    races = Race.at_level(filters["level"])
    races = races.in_state(State.includes(:jurisdiction).find(filters["state_id"])) if filters["state_id"].present?
    races = races.in_county(County.find(filters["county_id"])) if filters["county_id"].present?
    endorsements = Endorsement.includes(:endorser, candidacy: [ :citizen, { race: [ :election, { office: [ :position, { jurisdiction: :jurisdictionable } ] } ] } ])
      .for_races(races)
      .order(endorsed_on: :desc, id: :desc)
    endorsements = endorsements.matching(filters["q"]) if filters["q"].present?
    endorsements = endorsements.where(kind: filters["kind"]) if filters["kind"].present?
    endorsements = endorsements.current if filters["status"] == "current"
    endorsements = endorsements.where.not(withdrawn_on: nil) if filters["status"] == "withdrawn"
    organization = Organization.find(filters["organization_id"]) if filters["organization_id"].present?
    endorsements = endorsements.where(endorser: organization) if organization
    counties = County.includes(:state).order(:name, :id)
    counties = counties.where(state_id: filters["state_id"]) if filters["state_id"].present?
    pagy, records = pagy(endorsements)
    render Views::Endorsements::IndexView.new(endorsements: records, pagy: pagy, filters: filters, organization: organization,
      states: State.order(:name), counties: counties)
  end

  def show
    endorsement = Endorsement.includes(:endorser, candidacy: [ :citizen, { race: [ :election, { office: [ :position, { jurisdiction: :jurisdictionable } ] } ] } ]).find(params[:id])
    render Views::Endorsements::ShowView.new(endorsement: endorsement)
  end

  private

  def filters
    @filters ||= params.permit(:q, :kind, :status, :organization_id, :state_id, :county_id, :level).to_h.tap do |values|
      if values["state_id"].present? && values["county_id"].present?
        values.delete("county_id") unless County.where(state_id: values["state_id"]).exists?(id: values["county_id"])
      end
    end
  end
end
