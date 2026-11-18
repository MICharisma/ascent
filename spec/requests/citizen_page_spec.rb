require "rails_helper"

# A citizen's page lists every candidacy, latest first, and leads to the latest one.
RSpec.describe "Citizen page", type: :request do
  let(:citizen) { create(:citizen, first_name: "Marisol", middle_name: nil, last_name: "Okafor", bio: nil) }
  let!(:earlier) do
    create(:candidacy, citizen: citizen, status: "active", race: create(:race, :completed, election: create(:election, :completed, name: "Calder Primary 2024", election_date: Date.new(2024, 6, 4))))
  end
  let!(:latest) do
    create(:candidacy, citizen: citizen, status: "active", party_label: "Harbor Party",
      race: create(:race, :active, election: create(:election, :active, name: "Calder General 2026", election_date: Date.new(2026, 11, 3))))
  end

  it "lists candidacies latest first and links to the latest" do
    get citizen_path(citizen)

    page = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(page.css(".breadcrumb a").map(&:text)).to eq([ "Citizens" ])
    expect(page.at_css("h1").text).to eq("Marisol Okafor")
    expect(page.css("#citizen-candidacies .list-row-meta").map(&:text).map { it.split(" · ").first }).to eq([ "Calder General 2026", "Calder Primary 2024" ])
    expect(page.at_css(".page-header .pill-button")["href"]).to eq(candidacy_path(latest))
    expect(response.body).to include("1 earlier candidacy below.", "Harbor Party")
  end

  it "links their official channels, and only official ones" do
    Channel.create!(owner: citizen, platform: "bluesky", handle: "marisolokafor", official: true, url: "https://bsky.app/profile/marisolokafor")
    Channel.create!(owner: citizen, platform: "x", handle: "okafor_fan", official: false)

    get citizen_path(citizen)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css(%(a[href="https://bsky.app/profile/marisolokafor"])).text).to eq("marisolokafor · Bluesky")
    expect(response.body).not_to include("okafor_fan")
  end

  it "finds citizens by name" do
    get citizens_path, params: { q: "marisol ok" }

    expect(response.body).to include(%(id="list_item_citizen_#{citizen.id}"))

    get citizens_path, params: { q: "Nobody" }

    expect(response.body).not_to include(%(id="list_item_citizen_#{citizen.id}"))
    expect(response.body).to include("No citizens match")
  end
end
