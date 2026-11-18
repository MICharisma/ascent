require "rails_helper"

RSpec.describe "Consolidated candidacy links", type: :request do
  it "permanently redirects the old public page to its surviving candidacy" do
    survivor = create(:candidacy)
    CandidacyMerge.create!(old_candidacy_id: 987654321, candidacy: survivor, performed_by: "maintainer", snapshot: {})
    get candidacy_path(987654321)
    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to(candidacy_path(survivor))
  end

  it "keeps edit authorization on an old link" do
    survivor = create(:candidacy)
    CandidacyMerge.create!(old_candidacy_id: 987654321, candidacy: survivor, performed_by: "maintainer", snapshot: {})
    get edit_candidacy_path(987654321)
    expect(response).to redirect_to(new_voter_session_path)
  end
end
