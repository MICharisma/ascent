require "rails_helper"

# An election's page pairs a date stub (with a square for each day left) with the ballot as a numbered
# sheet of contests. Offices with several seats collapse into seat chips that show the voter's progress,
# and long ballots fold after ten contests.
RSpec.describe "Election page", type: :request do
  include_context "Port Merritt ballot"

  let(:election) { create(:election, jurisdiction: port_merritt, name: "Port Merritt General Election", election_date: 9.days.from_now, status: "upcoming") }

  def race_for(title, seat_code: nil, candidates: [])
    office = create(:office, position: Position.find_or_create_by!(title: title), jurisdiction: port_merritt, seat_code: seat_code)
    create(:race, election: election, office: office, status: "upcoming").tap do |race|
      candidates.each { |name| create(:candidacy, race: race, citizen: create(:citizen, first_name: name, middle_name: nil, last_name: "Okafor")) }
    end
  end

  it "shows the date stub and the ballot to a visitor, and invites them to sign in" do
    race_for("Mayor", candidates: %w[Dana Ruth])

    get election_path(election)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Port Merritt General Election", "9 days to go", "One square per day", "The ballot")
    expect(response.body).to include("01", "Mayor", "Sign in to build a mountain")
    expect(response.body).to include('<span class="candidate-given">Dana </span><strong class="candidate-surname">Okafor</strong></button>')
    expect(response.body.scan("countdown-cell").size).to eq(10)
  end

  it "folds an office with several seats into chips in natural order, showing the resident's progress" do
    seats = [ "DISTRICT_10", "DISTRICT_2", "DISTRICT_7" ].map { race_for("City Council", seat_code: it, candidates: %w[Ana]) }
    Mountain.new(voter: voter, race: seats.second).publish!(ratings: { seats.second.candidacies.first.id => 300 }, baseline: 200)
    sign_in voter

    get election_path(election)

    expect(response.body).to include("Your ballot", "Open my ballot", "3 seats")
    expect(response.body.scan(/seat-chip-label">([^<]+)</).flatten).to eq([ "District 2", "District 7", "District 10" ])
    expect(response.body).to include("seat-chip seat-chip-saved")
  end

  it "offers Open mountain, and Results, only once a mountain is saved" do
    mayor = race_for("Mayor", candidates: %w[Dana])
    race_for("Clerk", candidates: %w[Ruth])
    sign_in voter

    get election_path(election)
    expect(response.body).not_to include(race_results_path(mayor))

    Mountain.new(voter: voter, race: mayor).publish!(ratings: { mayor.candidacies.first.id => 300 }, baseline: 200)
    get election_path(election)

    expect(response.body).to include("state-chip-saved", 'title="Open mountain"', race_results_path(mayor))
    expect(response.body.scan(%r{/races/\d+/results}).size).to eq(1)
  end

  it "shows ten contests and folds the rest" do
    12.times { |n| race_for("Commissioner #{n + 1}") }

    get election_path(election)

    expect(response.body).to include("Show 2 more contests")
    expect(response.body.scan('class="contest"').size).to eq(12)
  end

  it "lets a mock election's creator remove it from its page" do
    mock = MockElection.new(name: "Classroom vote", election_date: 2.weeks.from_now.to_date, jurisdiction_id: port_merritt.id, creator: voter,
                            races: [ { title: "Class President", candidates: [ "Avery Lin", "Jordan Reyes" ] } ]).save!
    sign_in voter

    get election_path(mock)

    expect(response.body).to include("Mock election", "Invented candidates · made by Rosa", "Remove mock election", "Build your mountain")
  end

  it "can be followed like a race" do
    sign_in voter

    post engagements_path, params: { engageable_type: "Election", engageable_id: election.id, kind: "follow" }

    expect(voter.engagements.follow.sole.engageable).to eq(election)
  end
end
