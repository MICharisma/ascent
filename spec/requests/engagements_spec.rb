require 'rails_helper'

# Visitors save, favorite, follow, and hide candidacies, races, issues, stances, and citizens.
# Each button toggles one Engagement, and the bar updates in place through a Turbo Stream.
RSpec.describe "Engagements", type: :request do
  let(:lansing_voter) { create(:voter, first_name: "Dana", last_name: "Okoro", email: "dana.okoro@example.com") }
  let(:flint_voter) { create(:voter, first_name: "Luis", last_name: "Ferreira", email: "luis.ferreira@example.com") }
  let!(:housing_issue) { create(:affordable_housing_issue) }
  let(:turbo_stream) { { "Accept" => "text/vnd.turbo-stream.html" } }

  def mark(record, kind, headers: turbo_stream)
    post engagements_path, params: { engageable_type: record.class.name, engageable_id: record.id, kind: kind }, headers: headers
  end

  describe "marking a record" do
    it "asks a signed-out visitor to sign in instead of saving anything" do
      mark housing_issue, :bookmark, headers: {}

      expect(response).to redirect_to(new_voter_session_path)
      expect(Engagement.count).to eq(0)
    end

    it "saves the mark and replaces the record's action bar with the marked state" do
      sign_in lansing_voter

      mark housing_issue, :bookmark

      expect(lansing_voter.engagements.bookmark.where(engageable: housing_issue)).to exist
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(<turbo-stream action="replace" target="action_bar_issue_#{housing_issue.id}">))
      expect(response.body).to match(%r{aria-pressed="true"[^>]*><svg[^>]*icon-bookmark-check.*?</svg><span class="action-label">Saved</span>})
    end

    it "keeps one mark of each kind however many times the button is pressed" do
      sign_in lansing_voter

      2.times { mark housing_issue, :favorite }

      expect(lansing_voter.engagements.favorite.count).to eq(1)
    end

    it "goes back to the page without JavaScript" do
      sign_in lansing_voter

      mark housing_issue, :follow, headers: { "HTTP_REFERER" => issues_url }

      expect(response).to redirect_to(issues_url)
    end

    it "refuses records visitors cannot engage with and unknown kinds" do
      sign_in lansing_voter

      post engagements_path, params: { engageable_type: "Voter", engageable_id: flint_voter.id, kind: "bookmark" }, headers: turbo_stream
      expect(response).to have_http_status(:not_found)

      mark housing_issue, :endorse
      expect(response).to have_http_status(:unprocessable_content)
      expect(Engagement.count).to eq(0)
    end
  end

  describe "removing a mark" do
    let!(:favorite) { create(:engagement, voter: lansing_voter, engageable: housing_issue, kind: :favorite) }

    it "lets the voter who made it take it back" do
      sign_in lansing_voter

      delete engagement_path(favorite), headers: turbo_stream

      expect(Engagement.exists?(favorite.id)).to be(false)
      expect(response.body).to match(%r{aria-pressed="false"[^>]*><svg[^>]*icon-heart.*?</svg><span class="action-label">Favorite</span>})
    end

    it "does not let another voter remove it" do
      sign_in flint_voter

      delete engagement_path(favorite), headers: turbo_stream

      expect(Engagement.exists?(favorite.id)).to be(true)
    end
  end

  it "shows other visitors how many people favorite a record, but not who saved it" do
    create(:engagement, voter: lansing_voter, engageable: housing_issue, kind: :favorite)
    create(:engagement, voter: lansing_voter, engageable: housing_issue, kind: :bookmark)

    get issue_path(housing_issue)

    expect(response.body).to include('<span class="action-label">Favorite</span><span class="action-count">1</span>')
    expect(response.body).to include('<span class="action-label">Save</span></a>')
    expect(response.body).not_to match(%r{<span class="action-label">Save</span><span class="action-count">})
  end

  it "takes a hidden record out of that voter's lists only" do
    school_issue = create(:school_funding_issue)
    create(:engagement, voter: lansing_voter, engageable: school_issue, kind: :hide)

    sign_in lansing_voter
    get issues_path
    expect(response.body).not_to include("Inadequate School Funding")
    expect(response.body).to include("Affordable Housing Shortage")

    sign_in flint_voter
    get issues_path
    expect(response.body).to include("Inadequate School Funding")
  end

  describe "the saved page" do
    it "groups a voter's marks by kind, with the bar to undo each" do
      candidacy = create(:candidacy)
      create(:engagement, voter: lansing_voter, engageable: housing_issue, kind: :bookmark)
      create(:engagement, voter: lansing_voter, engageable: candidacy, kind: :follow)
      create(:engagement, voter: flint_voter, engageable: candidacy, kind: :favorite)

      sign_in lansing_voter
      get engagements_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h2>Saved</h2>", "<h2>Following</h2>")
      expect(response.body).not_to include("<h2>Favorites</h2>")
      expect(response.body).to include("Affordable Housing Shortage", candidacy.name)
      expect(response.body).to include(%(id="action_bar_candidacy_#{candidacy.id}"))
    end

    it "is only for signed-in voters" do
      get engagements_path

      expect(response).to redirect_to(new_voter_session_path)
    end
  end
end
