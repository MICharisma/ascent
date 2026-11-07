require "rails_helper"

# The mountain page autosaves dragging to a server draft, then saves or discards it. Each answer is the
# mountain as it now stands, so the page can show the unsaved-changes bar and the Your vote panel.
RSpec.describe "Mountain drafts", type: :request do
  let(:race) { create(:race, :active) }
  let(:voter) { create(:voter, first_name: "Rosa", last_name: "Delgado") }
  let!(:okafor) { create(:candidacy, race: race, citizen: create(:citizen, first_name: "Dana", middle_name: nil, last_name: "Okafor")) }
  let!(:lindqvist) { create(:candidacy, race: race, citizen: create(:citizen, first_name: "Theo", middle_name: nil, last_name: "Lindqvist")) }

  before { sign_in voter }

  it "keeps dragged ratings in a draft and answers with what saving would change" do
    patch draft_mountain_path(race), params: { ratings: { okafor.id => "360", lindqvist.id => "180" }, baseline: "280" }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      "progress" => "started", "baseline" => 280, "approved_candidacy_ids" => [ okafor.id ],
      "unsaved_changes" => { "candidacy_ids" => [ okafor.id, lindqvist.id ], "baseline" => [ 200, 280 ] },
      "baseline_changes_left_today" => 5
    )
    expect(Rating.count).to eq(0)
  end

  it "answers the page's autosave with fresh Your vote, allowance and save bar panels" do
    patch draft_mountain_path(race), params: { ratings: { okafor.id => "360" }, baseline: "280" },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('target="your-vote"', 'target="baseline-allowance"', 'target="mountain-save-bar"')
    expect(response.body).to include("2 unsaved changes", "Ratings: Dana Okafor", "Baseline 200 → 280", "Save mountain")
  end

  it "shows the mountain with its mode strip, Your vote panel and list view" do
    get edit_mountain_path(race)

    expect(response.body).to include("Pretend vote", "Your vote", "All changes saved", "Rate Dana Okafor", "Follow race")
    page = Nokogiri::HTML(response.body)
    notice = page.at_css(".race-header .mode-pretend")
    expect(notice.at_css(".mode-strip-text").text).to eq("counted separately")
    expect(notice.css("a, button")).to be_empty
    expect(page.at_css("input[name='baseline']")["value"]).to eq("200")
    expect(page.css("[data-role='baseline-slider']").map { it["value"] }).to eq([ "200", "200" ])
    expect(page.at_css(".baseline-label").text).to eq("Baseline: 200")
    expect(page.css(".no-rating")).to be_empty
    expect(page.at_css(".not-approved").text).not_to include("not rated")
    expect(page.at_css(".mountain-aside #mountain-save-bar")).to be_present
    expect(page.at_css(".mountain-footer .party-endorsements-toggle")).to be_present
  end

  it "saves the draft into the voter's mountain" do
    patch draft_mountain_path(race), params: { ratings: { okafor.id => "360" }, baseline: "280" }, as: :json

    post save_mountain_path(race)

    expect(response).to redirect_to(mountain_path(race, voter_id: voter.id))
    expect(flash[:notice]).to eq("Mountain saved.")
    expect(Rating.find_by!(voter: voter, candidacy: okafor).rating).to eq(360)
    expect(MountainDraft.count).to eq(0)
  end

  it "discards the draft" do
    patch draft_mountain_path(race), params: { baseline: "450" }, as: :json

    delete draft_mountain_path(race), as: :json

    expect(response.parsed_body).to include("progress" => "not_started", "baseline" => 200)
    expect(MountainDraft.count).to eq(0)
  end

  it "rejects a draft rating for a candidate in another race" do
    patch draft_mountain_path(race), params: { ratings: { create(:candidacy).id => "300" } }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["errors"]).to include(/not on this mountain/)
  end

  it "keeps another voter's draft private" do
    neighbor = create(:voter)

    patch draft_mountain_path(race), params: { voter_id: neighbor.id, baseline: "300" }, as: :json

    expect(MountainDraft.count).to eq(0)
  end

  describe "simulated data" do
    before { sign_in create(:voter, admin: true) }

    it "stays out of real races" do
      expect { post simulate_mountain_path(race) }.not_to change(Candidacy, :count)
      expect(flash[:alert]).to eq("Simulated data can only go in a mock election.")
    end
  end
end
