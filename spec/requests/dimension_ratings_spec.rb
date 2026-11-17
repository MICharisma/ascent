require "rails_helper"

# A signed-in voter rates a citizen's or a policy's curated qualities. Each save or clear answers
# with the redrawn row, touches only that voter's ratings, and leaves the mountain alone.
RSpec.describe "Dimension ratings", type: :request do
  let(:voter) { create(:voter, first_name: "Teodora", last_name: "Lindqvist") }
  let(:neighbor) { create(:voter, first_name: "Kwame", last_name: "Asante") }
  let(:citizen) { create(:citizen, first_name: "Marisol", middle_name: nil, last_name: "Okafor", bio: nil) }
  let(:policy) { create(:policy) }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  def rate(rated_path, key, value)
    post rated_path, params: { dimension_rating: { dimension_key: key, value: value } }, headers: turbo, as: :json
  end

  def clear(rated_path, key)
    delete rated_path, params: { dimension_rating: { dimension_key: key } }, headers: turbo, as: :json
  end

  describe "rating" do
    before { sign_in voter }

    it "saves a citizen's trustworthiness and answers with the saved row" do
      rate citizen_dimension_ratings_path(citizen), "ascent.citizen.trustworthiness", 230

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(target="#{ActionView::RecordIdentifier.dom_id(citizen, :trustworthiness_rating)}"), "+230", "Saved", "Clear")
      expect(voter.dimension_ratings.sole).to have_attributes(rated: citizen, dimension_key: "ascent.citizen.trustworthiness", value: 230, dimension_version: 1)
    end

    it "replaces the voter's earlier score instead of adding another" do
      rate citizen_dimension_ratings_path(citizen), "ascent.citizen.competence", 100
      rate citizen_dimension_ratings_path(citizen), "ascent.citizen.competence", 0

      expect(voter.dimension_ratings.pluck(:value)).to eq([ 0 ])
      expect(voter.dimension_rating_revisions.order(:id).pluck(:event, :value)).to eq([ [ "rate", 100 ], [ "change", 0 ] ])
    end

    it "rates a policy's own qualities" do
      rate policy_dimension_ratings_path(policy), "ascent.policy.affects_me", 480

      expect(response).to have_http_status(:ok)
      expect(policy.dimension_ratings.sole).to have_attributes(voter: voter, value: 480)
    end

    it "rejects another model's quality and a score off the scale without writing" do
      rate citizen_dimension_ratings_path(citizen), "ascent.policy.fairness", 100
      expect(response).to have_http_status(:unprocessable_content)

      rate citizen_dimension_ratings_path(citizen), "ascent.citizen.familiarity", 900
      expect(response).to have_http_status(:unprocessable_content)
      expect(DimensionRating.count).to eq(0)
    end

    it "clears only the voter's own score and records the clearing" do
      create(:dimension_rating, :capable_candidate, voter: neighbor, rated: citizen)
      create(:dimension_rating, :capable_candidate, voter: voter, rated: citizen, value: 150)

      clear citizen_dimension_ratings_path(citizen), "ascent.citizen.competence"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Not rated", "Rate neutral")
      expect(citizen.dimension_ratings.pluck(:voter_id)).to eq([ neighbor.id ])
      expect(voter.dimension_rating_revisions.order(:id).pluck(:event)).to eq(%w[rate clear])
    end

    it "leaves mountain ratings and baselines untouched" do
      expect { rate citizen_dimension_ratings_path(citizen), "ascent.citizen.familiarity", 300 }
        .not_to change { [ Rating.count, VoterRaceBaseline.count, RatingArchive.count ] }
    end
  end

  it "turns away a visitor who isn't signed in" do
    rate citizen_dimension_ratings_path(citizen), "ascent.citizen.familiarity", 300

    expect(response).to redirect_to(new_voter_session_path)
    expect(DimensionRating.count).to eq(0)
  end

  describe "on the citizen page" do
    before do
      create(:dimension_rating, :well_known_candidate, voter: neighbor, rated: citizen)
      create(:dimension_rating, :well_known_candidate, voter: create(:voter), rated: citizen, value: 200)
    end

    it "asks a visitor to sign in and shows no scores or averages" do
      get citizen_path(citizen)

      section = Nokogiri::HTML(response.body).at_css(".dimension-ratings")
      expect(section.text).to include("Sign in to rate this citizen on 3 qualities.")
      expect(section.css(".dimension-rating-row")).to be_empty
      expect(response.body).not_to include("Voters average")
    end

    it "shows a signed-in voter the voters' average, opens rated rows and offers the rest" do
      create(:dimension_rating, :distrusted_candidate, voter: voter, rated: citizen)
      sign_in voter
      get citizen_path(citizen)

      page = Nokogiri::HTML(response.body)
      rows = page.css(".dimension-rating-row").to_h { [ it["data-key"].split(".").last, it ] }
      expect(rows.keys).to eq(%w[familiarity trustworthiness competence])
      expect(rows["trustworthiness"]["hidden"]).to be_nil
      expect(rows["trustworthiness"].at_css(".dimension-rating-value").text).to eq("-80")
      expect(rows["familiarity"]["hidden"]).not_to be_nil
      expect(rows["familiarity"].at_css(".dimension-rating-summary").text).to eq("Voters average +310 · 2 ratings")
      expect(page.css(".dimension-suggestions button").map(&:text)).to eq(%w[Familiarity Competence])
      expect(page.css(".dimension-select option").map(&:text)).to eq([ "Choose a quality", "Familiarity", "Trustworthiness", "Competence" ])
      expect(JSON.parse(rows["competence"]["data-dimension"])).to include("minimum" => -100, "maximum" => 500, "coarse_step" => 10, "fine_step" => 1)
    end
  end

  it "shows a policy's qualities on its page" do
    sign_in voter
    get policy_path(policy)

    expect(Nokogiri::HTML(response.body).css(".dimension-suggestions button").map(&:text)).to eq([ "Effectiveness", "Fairness", "Affects me" ])
  end
end
