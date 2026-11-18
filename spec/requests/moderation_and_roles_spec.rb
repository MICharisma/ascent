require "rails_helper"

RSpec.describe "Roles, heaven-banning, and channel reviews", type: :request do
  let(:admin) { create(:admin_voter) }
  let(:moderator) { create(:moderator_voter) }
  let(:reviewer) { create(:reviewer_voter) }
  let(:voter) { create(:voter, first_name: "Marisol", last_name: "Vega", public_influencer: true) }
  let(:neighbor) { create(:voter, first_name: "Rosa", last_name: "Delgado") }

  def page
    Nokogiri::HTML(response.body)
  end

  describe "Private voting activity" do
    let(:race) { create(:race, :active) }
    let(:candidacy) { create(:candidacy, race: race) }
    let!(:baseline) { create(:voter_race_baseline, voter: voter, race: race, baseline: 237) }
    let!(:rating) { create(:rating, voter: voter, candidacy: candidacy, rating: 401) }

    it "allows moderation without exposing another voter's voting activity" do
      sign_in moderator

      get voter_path(voter)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Hide profile")
      expect(response.body).not_to include("Races taken part in", "baseline 237", race.office.name)

      [ rating_path(rating), voter_race_baseline_path(baseline) ].each do |path|
        get path
        expect(response).to redirect_to(root_path)
      end
    end

    it "keeps voting activity visible to the voter and admins" do
      [ voter, admin ].each do |actor|
        sign_in actor
        get voter_path(voter)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Races taken part in", "baseline 237", race.office.name)
      end
    end
  end

  describe "Voter roles" do
    it "supports admin, moderator, and reviewer roles with capability hierarchy" do
      expect(admin).to be_admin
      expect(admin.can_moderate?).to be(true)
      expect(admin.can_review?).to be(true)

      expect(moderator).to be_moderator
      expect(moderator).not_to be_admin
      expect(moderator.can_moderate?).to be(true)
      expect(moderator.can_review?).to be(true)

      expect(reviewer).to be_reviewer
      expect(reviewer).not_to be_admin
      expect(reviewer.can_moderate?).to be(false)
      expect(reviewer.can_review?).to be(true)

      expect(voter.role).to be_nil
      expect(voter.can_moderate?).to be(false)
      expect(voter.can_review?).to be(false)

      expect(build(:voter, role: "superuser")).not_to be_valid
    end

    it "cannot be assigned or escalated through registration or profile update parameters" do
      post voter_registration_path, params: {
        voter: {
          first_name: "Attempt",
          last_name: "Escalation",
          email: "attempt@example.com",
          password: "password123",
          password_confirmation: "password123",
          role: "admin",
          profile_hidden: true
        }
      }
      created = Voter.find_by!(email: "attempt@example.com")
      expect(created.role).to be_nil

      sign_in voter
      patch voter_path(voter), params: { voter: { first_name: "Marisol", role: "admin", profile_hidden: true } }
      expect(voter.reload.role).to be_nil
      expect(voter.profile_hidden).to be(false)
    end
  end

  describe "Heaven-banning (profile_hidden)" do
    before do
      voter.invites.create!(invitee: neighbor)
      voter.voter_links.create!(label: "My Civic Blog", url: "https://example.com/blog")
      voter.voter_statements.create!(body: "Local budgets should be transparent.")
    end

    it "allows moderators and admins to hide and unhide a voter's profile" do
      [ moderator, admin ].each do |staff|
        sign_in staff
        get voters_path
        expect(response).to have_http_status(:ok)

        get voter_path(voter)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Hide profile")

        patch hide_profile_voter_path(voter), params: { voter: { profile_hidden: "1" } }
        expect(response).to redirect_to(voter_path(voter))
        expect(voter.reload.profile_hidden?).to be(true)

        patch hide_profile_voter_path(voter), params: { voter: { profile_hidden: "0" } }
        expect(voter.reload.profile_hidden?).to be(false)
      end
    end

    it "prevents regular voters, reviewers, or self-moderation from changing profile_hidden" do
      [ neighbor, reviewer, voter ].each do |actor|
        sign_in actor
        patch hide_profile_voter_path(voter), params: { voter: { profile_hidden: "1" } }
        expect(response).to redirect_to(root_path)
        expect(voter.reload.profile_hidden?).to be(false)
      end
    end

    it "hides a heaven-banned voter's influencer profile, links, and statements from others while keeping them visible to the voter themselves" do
      voter.update!(profile_hidden: true)

      get influencer_path(token: voter.invite_token)
      expect(response).to have_http_status(:not_found)

      get invites_path
      expect(response.body).to include("Anonymous influencer")
      expect(response.body).not_to include("Marisol Vega", voter.invite_token)

      sign_in neighbor
      get influencer_path(token: voter.invite_token)
      expect(response).to have_http_status(:not_found)

      sign_in neighbor
      expect do
        post invites_path, params: { token: voter.invite_token }
      end.not_to change(Invite, :count)
      expect(response).to have_http_status(:not_found)

      sign_in neighbor
      get invites_path
      expect(response.body).to include("Anonymous influencer")
      expect(response.body).not_to include("Marisol Vega", voter.invite_token)

      sign_in voter
      get influencer_path(token: voter.invite_token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Marisol Vega", "My Civic Blog", "Local budgets should be transparent.")

      get invites_path
      expect(response.body).to include("Marisol Vega", "You")

      get influencer_profile_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Civic Blog", "Local budgets should be transparent.")

      get voter_path(voter)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Profile visibility", "Hidden", "Unhide profile")
    end

    it "continues to tabulate a heaven-banned voter's ratings and baselines in race results" do
      voter.update!(profile_hidden: true)
      race = create(:race, :active)
      candidacy = create(:candidacy, race: race, status: "active")

      Rating.create!(voter: voter, candidacy: candidacy, rating: 400)
      VoterRaceBaseline.create!(voter: voter, race: race, baseline: 200)

      results = RaceResults.new(race, group: "visitor")
      expect(results.mountain_count).to eq(1)
      expect(results.approval_shares[candidacy.id]).to eq(100)
    end
  end

  describe "Candidate social channel reviews" do
    let(:citizen) { create(:citizen, first_name: "Elena", middle_name: nil, last_name: "Rostova") }
    let!(:pending_channel) do
      Channel.create!(
        owner: citizen,
        platform: "bluesky",
        handle: "elenarostova",
        url: "https://bsky.app/profile/elenarostova",
        official: false,
        review_status: "pending"
      )
    end

    it "links the review queue from navigation only for staff with review permission" do
      [ nil, voter, reviewer, moderator, admin ].each do |actor|
        sign_in actor if actor
        get root_path
        expect(response).to have_http_status(:ok)
        links = page.css("nav a").map { it["href"] }
        if actor&.can_review?
          expect(links).to include(channels_path)
        else
          expect(links).not_to include(channels_path)
        end
        sign_out actor if actor
      end
    end

    it "preserves channel reviews when an admin deletes the reviewer" do
      pending_channel.approve!(reviewer)
      reviewed_at = pending_channel.reviewed_at
      sign_in admin

      delete voter_path(reviewer)

      expect(response).to redirect_to(voters_path)
      expect(Voter.exists?(reviewer.id)).to be(false)
      expect(pending_channel.reload).to have_attributes(
        official: true, review_status: "approved", reviewed_by_id: nil, reviewed_at: reviewed_at
      )
    end

    it "allows reviewers to delete their own accounts after reviewing a channel" do
      pending_channel.reject!(reviewer)
      sign_in reviewer

      delete voter_registration_path

      expect(response).to redirect_to(root_path)
      expect(Voter.exists?(reviewer.id)).to be(false)
      expect(pending_channel.reload).to have_attributes(official: false, review_status: "rejected", reviewed_by_id: nil)
    end

    it "restricts the channel review queue to reviewers, moderators, and admins" do
      get channels_path
      expect(response).to redirect_to(new_voter_session_path)

      sign_in voter
      get channels_path
      expect(response).to redirect_to(root_path)
      patch channel_path(pending_channel), params: { review_status: "approved" }
      expect(response).to redirect_to(root_path)
      expect(pending_channel.reload.review_status).to eq("pending")
    end

    it "allows a reviewer, moderator, or admin to approve and reject candidate channels" do
      get citizen_path(citizen)
      expect(response.body).not_to include("elenarostova · Bluesky")

      sign_in reviewer
      get channels_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("elenarostova on Bluesky", "Elena Rostova")

      patch channel_path(pending_channel), params: { review_status: "approved" }
      expect(response).to redirect_to(channels_path)
      expect(pending_channel.reload).to have_attributes(
        official: true,
        review_status: "approved",
        reviewed_by: reviewer
      )
      expect(pending_channel.reviewed_at).to be_present

      get citizen_path(citizen)
      expect(response.body).to include("elenarostova · Bluesky")

      sign_in moderator
      patch channel_path(pending_channel), params: { review_status: "rejected" }
      expect(response).to redirect_to(channels_path)
      expect(pending_channel.reload).to have_attributes(
        official: false,
        review_status: "rejected",
        reviewed_by: moderator
      )

      get citizen_path(citizen)
      expect(response.body).not_to include("elenarostova · Bluesky")
    end
  end
end
