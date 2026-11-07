# The card a ballot opens on a candidate's name, loaded into its Turbo frame when first shown.
class CandidacyCardsController < ApplicationController
  def show
    candidacy = Candidacy.includes(:citizen, :ballot_lines, race: { office: :position }).find(params.expect(:id))
    authorize! candidacy, to: :show?
    render Views::Candidacies::Card.new(candidacy: candidacy), layout: false
  end
end
