require "rails_helper"
require "vips"

RSpec.describe "Public mountains", type: :request do
  let(:voter) { create(:voter, first_name: "Rosa", last_name: "Delgado") }
  let(:race) { create(:race, :active) }
  let!(:candidate) { create(:candidacy, race: race, status: "active", citizen: create(:citizen, first_name: "Dana", middle_name: nil, last_name: "Okafor")) }
  let(:mountain) { Mountain.new(voter: voter, race: race) }

  def save_mountain
    mountain.publish!(ratings: { candidate.id => 360 }, baseline: 280)
  end

  it "starts private and shows publication controls only to the owner" do
    save_mountain
    sign_in voter
    get mountain_path(race)
    expect(response.body).to include("Make public", "Your mountain is private")
    expect(response.body).not_to include('property="og:image"')
    expect(PublicMountain.count).to eq(0)

    sign_in create(:voter, admin: true)
    get mountain_path(race, voter_id: voter.id)
    expect(response.body).not_to include("Make public")
  end

  it "publishes only saved ratings, stores a real PNG, and provides anonymous Open Graph previews" do
    save_mountain
    mountain.revise_draft!(ratings: { candidate.id => 111 }, baseline: 450)
    sign_in voter
    post share_mountain_path(race)
    expect(response).to redirect_to(mountain_path(race))
    publication = PublicMountain.find_by!(voter: voter, race: race)
    expect(publication.snapshot).to include("voter_name" => "Rosa Delgado", "baseline" => 280)
    expect(publication.snapshot.fetch("candidates").sole).to include("name" => "Dana Okafor", "rating" => 360)
    image = Vips::Image.new_from_buffer(publication.preview_png, "")
    expect([ image.width, image.height ]).to eq([ 1200, 630 ])

    sign_out voter
    get public_mountain_path(publication), headers: { "User-Agent" => "facebookexternalhit/1.1" }
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("meta[property='og:title']")["content"]).to eq("Rosa Delgado's mountain")
    expect(page.at_css("meta[property='og:url']")["content"]).to eq(public_mountain_url(publication))
    image_url = page.at_css("meta[property='og:image']")["content"]
    expect(image_url).to start_with(public_mountain_url(publication, format: :png))
    expect(page.at_css("meta[property='og:image:width']")["content"]).to eq("1200")
    expect(page.css("form, input[name='ratings']")).to be_empty
    expect(page.at_css(".public-mountain-ratings").text).to include("Dana Okafor", "360", "Approved")
    expect(response.headers["Cache-Control"]).to include("no-store")

    get image_url, headers: { "User-Agent" => "Twitterbot/1.0" }
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.body.b).to eq(publication.preview_png.b)
    expect(response.headers["Cache-Control"]).to include("no-store")

    get mountain_path(race, voter_id: voter.id)
    expect(response).to redirect_to(new_voter_session_path)
    expect(MountainDraft.find_by!(voter: voter, race: race).baseline).to eq(450)
  end

  it "refuses empty and draft-only mountains" do
    sign_in voter
    post share_mountain_path(race)
    expect(flash[:alert]).to include("Save a baseline and at least one candidate rating")
    mountain.revise_draft!(ratings: { candidate.id => 360 }, baseline: 280)
    expect { post share_mountain_path(race) }.not_to change(PublicMountain, :count)
  end

  it "allows only the voter to publish or withdraw their mountain, including when it is public" do
    save_mountain
    publication = mountain.share!
    [ nil, create(:voter), create(:voter, admin: true) ].each do |viewer|
      sign_in viewer if viewer
      post share_mountain_path(race), params: { voter_id: voter.id }
      expect(response).to redirect_to(viewer ? root_path : new_voter_session_path)
      delete share_mountain_path(race), params: { voter_id: voter.id }
      expect(response).to redirect_to(viewer ? root_path : new_voter_session_path)
      patch draft_mountain_path(race), params: { voter_id: voter.id, baseline: 100 } unless viewer&.admin?
      sign_out viewer if viewer
    end
    expect(publication.reload.snapshot.fetch("baseline")).to eq(280)
    expect(MountainDraft.where(voter: voter)).to be_empty
  end

  it "withdraws the page and PNG and gives a later publication a new URL" do
    save_mountain
    publication = mountain.share!
    sign_in voter
    delete share_mountain_path(race)
    expect(flash[:notice]).to eq("Your mountain is now private.")
    delete share_mountain_path(race)
    sign_out voter
    get public_mountain_path(publication)
    expect(response).to have_http_status(:not_found)
    get public_mountain_path(publication, format: :png)
    expect(response).to have_http_status(:not_found)
    expect(mountain.share!.id).not_to eq(publication.id)
  end

  it "refreshes the same public URL and its image when the mountain is saved, never when a draft changes" do
    save_mountain
    publication = mountain.share!
    old_png = publication.preview_png
    old_version = publication.updated_at
    sign_in voter
    patch draft_mountain_path(race), params: { ratings: { candidate.id => 280 } }, as: :json
    expect(publication.reload.preview_png).to eq(old_png)
    expect(publication.updated_at).to eq(old_version)
    post save_mountain_path(race)
    expect(response).to redirect_to(mountain_path(race, voter_id: voter.id))
    expect(publication.reload.snapshot.fetch("candidates").sole.fetch("rating")).to eq(280)
    expect(publication.preview_png).not_to eq(old_png)
    get public_mountain_path(publication)
    expect(Nokogiri::HTML(response.body).at_css(".public-mountain-ratings").text).to include("Not approved")
    get mountain_path(race)
    expect(response.body).to include("Share mountain", "Make private", "Your saved ratings and baseline are public.")
  end

  it "keeps each race private until chosen and makes repeated publication idempotent" do
    save_mountain
    other = Mountain.new(voter: voter, race: create(:race, :active))
    first = mountain.share!
    expect(mountain.share!.id).to eq(first.id)
    expect(other.publication).to be_nil
    expect(PublicMountain.where(voter: voter).count).to eq(1)
  end

  it "refreshes primary-candidate inclusion without exposing drafts or other voters' ratings" do
    primary = create(:candidacy, race: race, status: "active", participation: "off_ballot", primary_candidacy: create(:candidacy))
    Rating.create!(voter: voter, candidacy: primary, rating: 450)
    Rating.create!(voter: create(:voter), candidacy: candidate, rating: 123)
    save_mountain
    publication = mountain.share!
    expect(publication.snapshot.fetch("candidates").length).to eq(1)
    sign_in voter
    patch primary_candidates_mountain_path(race), params: { included: "1" }
    expect(publication.reload.snapshot.fetch("candidates")).to include(include("rating" => 450, "off_ballot" => true))
    expect(publication.snapshot.fetch("candidates")).not_to include(include("rating" => 123))
    patch primary_candidates_mountain_path(race), params: { included: "0" }
    expect(publication.reload.snapshot.fetch("candidates").length).to eq(1)
  end

  it "rolls back publication when rendering fails" do
    save_mountain
    allow_any_instance_of(MountainPreview).to receive(:png).and_raise(MountainPreview::Error, "render failed")
    expect { mountain.share! }.to raise_error(MountainPreview::Error)
    expect(PublicMountain.count).to eq(0)
  end

  it "does not partially save a public mountain when refreshing its image fails" do
    save_mountain
    publication = mountain.share!
    mountain.revise_draft!(ratings: { candidate.id => 400 })
    allow_any_instance_of(MountainPreview).to receive(:png).and_raise(MountainPreview::Error, "render failed")
    expect { mountain.save! }.to raise_error(MountainPreview::Error)
    expect(Rating.find_by!(voter: voter, candidacy: candidate).rating).to eq(360)
    expect(MountainDraft.find_by!(voter: voter, race: race).ratings_by_candidacy[candidate.id]).to eq(400)
    expect(publication.reload.snapshot.fetch("candidates").sole.fetch("rating")).to eq(360)
  end
end
