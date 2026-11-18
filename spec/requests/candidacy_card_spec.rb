require "rails_helper"

# A name on the ballot opens a card: major endorsements, residents' support from their saved
# mountains, and links to the citizen and candidacy pages. It loads lazily into its own Turbo frame.
RSpec.describe "Candidate card", type: :request do
  let(:race) { create(:race, :active) }
  let(:okafor) { create(:candidacy, race: race, citizen: create(:citizen, first_name: "Dana", middle_name: nil, last_name: "Okafor"), party_label: nil) }
  let(:lindqvist) { create(:candidacy, race: race, citizen: create(:citizen, first_name: "Theo", middle_name: nil, last_name: "Lindqvist"), party_label: nil) }

  def mountain!(ratings)
    voter = create(:voter)
    VoterRaceBaseline.create!(voter: voter, race: race, baseline: 250, counted_as: "resident")
    ratings.each { |candidacy, rating| Rating.create!(voter: voter, candidacy: candidacy, rating: rating) }
  end

  it "names major endorsements strongest first, leaving out weak and withdrawn ones" do
    create(:endorsement, candidacy: okafor, endorser: create(:organization, :media), strength: 4, endorsed_on: Date.new(2026, 9, 1))
    create(:endorsement, :major, candidacy: okafor, endorser: create(:organization, :union))
    create(:endorsement, :minor, candidacy: okafor, endorser: create(:organization, name: "Garden Club"))
    create(:endorsement, :major, :withdrawn, candidacy: okafor, endorser: create(:organization, name: "Old Guard PAC"))

    get candidacy_card_path(okafor)

    expect(response.body).to include("turbo-frame", %(id="card_candidacy_#{okafor.id}"), 'target="_top"')
    expect(response.body.index("Harbor Workers Union Local 12")).to be < response.body.index("Port Merritt Ledger")
    expect(response.body).to include("Endorsed · Sep 2026")
    expect(response.body).not_to include("Garden Club", "Old Guard PAC")
    expect(response.body).to include(citizen_path(okafor.citizen), candidacy_path(okafor))
  end

  it "shows support from the first saved mountain, and says when there is none" do
    get candidacy_card_path(okafor)
    expect(response.body).to include("No resident has saved a mountain for this race yet.")

    mountain!({ okafor => 400 })
    get candidacy_card_path(okafor)

    expect(response.body).to include("100%", "approve", "400", "From 1 saved mountain.")
  end

  it "shows residents' approval, first choice and average rating once there are enough" do
    6.times { mountain!({ okafor => 300, lindqvist => 450 }) }
    4.times { mountain!({ okafor => 400, lindqvist => 100 }) }

    get candidacy_card_path(okafor)

    expect(response.body).to include("100%", "approve", "40%", "rate them highest", "340", "average rating", "From 10 saved mountains.")
  end

  it "opens from a name on the election's ballot" do
    okafor

    get election_path(race.election)

    expect(response.body).to include(%(popovertarget="candidate-popover-#{okafor.id}"), %(src="#{candidacy_card_path(okafor)}"), 'loading="lazy"')
  end
end
