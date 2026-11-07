require 'rails_helper'

# A primary is a race for a nomination: an Office whose position is Nominee, naming the office it
# nominates for and the organization that nominates. Everyone who ran in a primary can then stand in
# a simulated general, where approval voting may favor a candidate who lost the primary.
RSpec.describe "Nominations", type: :model do
  let(:georgia) { create(:state, name: "Georgia", code: "GA") }
  let(:jurisdiction) { create(:jurisdiction, jurisdictionable: georgia) }
  let(:year) { create(:year, year: 2026) }
  let(:governor) { create(:office, position: create(:position, :executive, title: "Governor"), jurisdiction: jurisdiction) }
  let(:nominee) { Position.create!(title: Position::NOMINEE_TITLE, branch: :executive) }
  let(:democrats) { Party.create!(name: "Democratic Party", state: georgia) }
  let(:republicans) { Party.create!(name: "Republican Party", state: georgia) }

  def nomination(organization, count: 1)
    Office.create!(position: nominee, jurisdiction: jurisdiction, nominee_for: governor, nominating_organization: organization, nominee_count: count, is_active: true)
  end

  def race_in(kind, office, date)
    election = Election.find_or_create_by!(jurisdiction: jurisdiction, year: year, kind: kind) do |record|
      record.name = "Georgia #{kind.humanize} Election 2026"
      record.election_date = date
      record.status = "upcoming"
      record.is_mock = false
      record.is_historical = false
    end
    Race.create!(election: election, office: office, status: "upcoming")
  end

  def candidacy(race, given, surname)
    Candidacy.create!(race: race, citizen: create(:citizen, first_name: given, middle_name: nil, last_name: surname), status: "active")
  end

  it "names the organization and the office it nominates for" do
    expect(nomination(democrats).name).to eq("Democratic Party nominee for Governor of Georgia")
  end

  describe "gathering primary candidates into the general" do
    let(:general) { race_in("general", governor, Date.new(2026, 11, 3)) }
    let(:democratic_primary) { race_in("primary", nomination(democrats), Date.new(2026, 5, 19)) }
    let(:republican_primary) { race_in("primary", nomination(republicans), Date.new(2026, 5, 19)) }
    let!(:okafor) { candidacy(democratic_primary, "Marisol", "Okafor") }
    let!(:pritchett) { candidacy(democratic_primary, "Dwayne", "Pritchett") }
    let!(:voss) { candidacy(republican_primary, "Harlan", "Voss") }
    let!(:general_okafor) { Candidacy.create!(race: general, citizen: okafor.citizen, status: "active") }

    it "gives each primary candidate not on the general's ballot an off-ballot candidacy there" do
      added = Race.gather_primary_candidates!

      expect(general.nomination_races).to contain_exactly(democratic_primary, republican_primary)
      expect(added.map { it.citizen.last_name }).to contain_exactly("Pritchett", "Voss")
      expect(general.candidacies.reload.map { [ it.citizen.last_name, it.participation, it.primary_candidacy ] })
        .to contain_exactly([ "Okafor", "active", nil ], [ "Pritchett", "off_ballot", pritchett ], [ "Voss", "off_ballot", voss ])
      expect(Race.gather_primary_candidates!).to be_empty
      expect(general.candidacies.find_by!(primary_candidacy: voss).ballot_summary).to eq("Off the ballot; ran in the Republican Party primary")
    end

    it "includes a runoff candidate once and leaves out a primary candidate who withdrew" do
      runoff = race_in("primary_runoff", democratic_primary.office, Date.new(2026, 6, 16))
      candidacy(runoff, "Dwayne", "Pritchett").update!(citizen: pritchett.citizen)
      voss.update!(status: "withdrawn")

      Race.gather_primary_candidates!

      expect(general.candidacies.from_primaries.map(&:primary_candidacy)).to contain_exactly(pritchett)
    end

    it "removes the off-ballot candidacy, and its ratings, of a candidate who leaves the primary" do
      Race.gather_primary_candidates!
      pritchett.update!(status: "disqualified")

      expect { Race.gather_primary_candidates! }.to change { general.candidacies.count }.by(-1)
      expect(general.candidacies.from_primaries.map(&:primary_candidacy)).to contain_exactly(voss)
    end

    it "leaves a primary's own field alone" do
      Race.gather_primary_candidates!

      expect(democratic_primary.candidacies.reload).to contain_exactly(okafor, pritchett)
    end
  end

  it "lets a top-two primary nominate two through a placeholder organization" do
    top_two = Organization.create!(name: "Georgia Top-Two Primary", kind: "nonpartisan_primary", state: georgia)

    expect(nomination(top_two, count: 2)).to have_attributes(nominee_count: 2, nominating_organization: top_two)
  end

  it "requires a nomination to name its office, organization, and count, under the Nominee position" do
    office = Office.new(position: governor.position, jurisdiction: jurisdiction, nominee_for: governor, is_active: true)

    expect(office).not_to be_valid
    expect(office.errors.messages).to include(
      nominating_organization: [ "is required for a nomination" ],
      nominee_count: [ "is required for a nomination" ],
      position: [ "must be Nominee for a nomination" ]
    )
  end

  it "keeps a nomination in the nominated office's jurisdiction" do
    elsewhere = create(:jurisdiction)
    office = Office.new(position: nominee, jurisdiction: elsewhere, nominee_for: governor, nominating_organization: democrats, nominee_count: 1, is_active: true)

    expect(office).not_to be_valid
    expect(office.errors[:jurisdiction]).to include("must be the nominated office's")
  end

  it "keeps parties as organizations with a state and no kind" do
    expect(democrats).to be_a(Organization)
    expect(Organization.find(democrats.id)).to be_a(Party)
    expect(Party.new(name: "Green Party", state: georgia, kind: "advocacy")).not_to be_valid
    expect(Organization.new(name: "Georgia AFL-CIO", kind: "union", state: georgia)).to be_valid
  end
end
