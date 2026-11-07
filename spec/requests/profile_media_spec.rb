require "rails_helper"

RSpec.describe "Profile media", type: :request do
  let(:citizen) do
    create(:citizen, first_name: "Marisol", middle_name: nil, last_name: "Vega")
  end
  let(:candidacy) { create(:candidacy, citizen: citizen) }
  let!(:portrait) do
    create(:image, url: "https://images.example.org/marisol.jpg", alt_text: "Portrait of Marisol Vega",
      credit: "Riverside Studio", source_url: "https://example.org/portraits/marisol").tap { citizen.images << it }
  end

  it "shows the same credited portrait on the citizen and candidacy pages" do
    [ citizen_path(citizen), candidacy_path(candidacy) ].each do |path|
      get path

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css(".profile-portrait-image")["src"]).to eq(portrait.url)
      expect(page.at_css(".profile-portrait-image")["alt"]).to eq("Portrait of Marisol Vega")
      expect(page.at_css(".profile-portrait-credit a")["href"]).to eq(portrait.source_url)
      expect(page.at_css(".profile-portrait-credit").text).to eq("Riverside Studio")
    end
  end

  it "separates personal and campaign channels and excludes another campaign's media" do
    earlier = create(:candidacy, citizen: citizen)
    personal = create(:channel, owner: citizen, official: true, platform: "bluesky", url: "https://bsky.app/profile/marisol.example")
    campaign = create(:channel, owner: candidacy, official: true, platform: "website", url: "https://example.org/marisol")
    old_channel = create(:channel, owner: earlier, official: true, platform: "website", url: "https://example.org/earlier")
    create(:communication, channel: personal, title: "A neighborhood walk", kind: "post")
    create(:communication, channel: campaign, title: "Current campaign priorities", kind: "platform")
    create(:communication, channel: old_channel, title: "Earlier campaign launch", kind: "platform")

    get candidacy_path(candidacy)

    expect(response.body).to include("Citizenal", "Campaign ·", "A neighborhood walk", "Current campaign priorities")
    expect(response.body).not_to include("Earlier campaign launch", old_channel.url)

    get citizen_path(citizen)

    expect(response.body).to include("Earlier campaign launch", old_channel.url)
  end

  it "keeps a photo source accessible when no credit text was supplied" do
    portrait.update!(credit: nil)

    get citizen_path(citizen)

    source = Nokogiri::HTML(response.body).at_css(".profile-portrait-credit a")
    expect(source["href"]).to eq(portrait.source_url)
    expect(source.text).to eq("Photo source")
  end

  it "loads provider players only after a play action, while retaining source links" do
    video = create(:communication, title: "Housing town hall", url: "https://youtu.be/M7lc1UVf-VE")
    video.communication_features.create!(candidacy: candidacy)

    get candidacy_path(candidacy)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("button[data-action='media-player#play']")["aria-label"]).to eq("Play Housing town hall")
    expect(page.at_css("template iframe")["src"]).to eq("https://www.youtube-nocookie.com/embed/M7lc1UVf-VE?autoplay=1&playsinline=1")
    expect(page.css("iframe").reject { it.ancestors("template").any? }).to be_empty
    expect(page.at_css(%(a[href="#{video.url}"])).text).to include("Open original")

    get citizen_path(citizen)
    expect(response.body).to include("Housing town hall")
  end

  it "provides native playback for direct videos and a fallback for removed or unsupported sources" do
    file = create(:communication, url: "https://media.example.org/intro.mp4", title: "Introduction")
    removed = create(:communication, url: "https://vimeo.com/123456", availability: "removed", archived_url: "https://archive.example.org/video")
    unsupported = create(:communication, url: "https://example.org/interview", title: "Local radio interview")
    [ file, removed, unsupported ].each { it.communication_features.create!(candidacy: candidacy) }

    get candidacy_path(candidacy)

    page = Nokogiri::HTML(response.body)
    expect(page.css("video").map { it["src"] }).to eq([ file.url ])
    expect(page.at_css("video[controls]")).to be_present
    expect(page.at_css("video")["autoplay"]).to be_nil
    expect(page.css("iframe")).to be_empty
    expect(response.body).to include("no longer available", "Archived copy", "Local radio interview")
  end

  it "lets an admin edit shared images and rejects executable URLs" do
    sign_in create(:voter, admin: true)

    placement = citizen.image_placements.sole
    patch citizen_path(citizen), params: { citizen: { image_placements_attributes: [ { id: placement.id,
      image_attributes: { id: portrait.id, url: "https://images.example.org/new.jpg", credit: "City Studio" } } ] } }
    expect(response).to redirect_to(citizen)
    expect(portrait.reload.credit).to eq("City Studio")

    patch citizen_path(citizen), params: { citizen: { image_placements_attributes: [ { id: placement.id,
      image_attributes: { id: portrait.id, url: "javascript:alert(1)" } } ] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(portrait.reload.url).to eq("https://images.example.org/new.jpg")
  end

  it "shows several ordered images, prefers campaign images, and deduplicates shared placements" do
    campaign = create(:image, alt_text: "Marisol at a campaign meeting")
    second = create(:image, alt_text: "Marisol volunteering")
    citizen.image_placements.create!(image: second, position: 1)
    candidacy.image_placements.create!(image: campaign, position: 0)
    candidacy.image_placements.create!(image: portrait, position: 1)

    get candidacy_path(candidacy)
    images = Nokogiri::HTML(response.body).css(".profile-portrait-image")
    expect(images.map { it["src"] }).to eq([ campaign.url, portrait.url, second.url ])

    get citizen_path(citizen)
    images = Nokogiri::HTML(response.body).css(".profile-portrait-image")
    expect(images.map { it["src"] }).to eq([ portrait.url, second.url ])
  end

  it "lets admins attach and unlink existing images on a candidacy without deleting them" do
    sign_in create(:voter, admin: true)
    patch candidacy_path(candidacy), params: { candidacy: { image_placements_attributes: [ { image_id: portrait.id } ] } }
    expect(response).to redirect_to(candidacy)
    expect(candidacy.images).to eq([ portrait ])

    placement = candidacy.image_placements.sole
    patch candidacy_path(candidacy), params: { candidacy: { image_placements_attributes: [ { id: placement.id, _destroy: "1" } ] } }
    expect(response).to redirect_to(candidacy)
    expect(candidacy.images.reload).to be_empty
    expect(citizen.images).to eq([ portrait ])
    expect(Image.exists?(portrait.id)).to be(true)
  end

  it "shows image management fields and retains invalid new image values" do
    sign_in create(:voter, admin: true)
    get edit_citizen_path(citizen)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Use an existing image", "Add a new image", "Remove from this profile")

    patch citizen_path(citizen), params: { citizen: { image_placements_attributes: [ { position: 0,
      image_attributes: { url: "javascript:alert(1)", credit: "City Studio" } } ] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("javascript:alert(1)", "City Studio")
    expect(citizen.images.reload).to eq([ portrait ])
  end

  it "prevents a non-admin from changing shared images" do
    sign_in create(:voter)
    patch citizen_path(citizen), params: { citizen: { image_placements_attributes: [ { id: citizen.image_placements.sole.id,
      image_attributes: { id: portrait.id, credit: "Changed" } } ] } }
    expect(response).to redirect_to(root_path)
    expect(portrait.reload.credit).to eq("Riverside Studio")
  end

  it "retains a reused image through a failed profile save and a form resubmission" do
    sign_in create(:voter, admin: true)
    reused = create(:image)
    patch citizen_path(citizen), params: { citizen: { last_name: "", image_placements_attributes: [ { image_id: reused.id } ] } }
    expect(response).to have_http_status(:unprocessable_content)

    form = Nokogiri::HTML(response.body).at_css("form[action='#{citizen_path(citizen)}']")
    pairs = form.css("input, select, textarea").filter_map do |input|
      next if input["name"].blank? || input["type"] == "file" || input.ancestors("fieldset[disabled]").any?
      next if input["type"] == "checkbox" && !input["checked"]
      value = case input.name
      when "select" then (input.at_css("option[selected]") || input.at_css("option"))["value"]
      when "textarea" then input.text
      else input["value"]
      end
      [ input["name"], value ]
    end
    values = Rack::Utils.parse_nested_query(URI.encode_www_form(pairs))
    values.fetch("citizen")["last_name"] = "Vega"
    patch citizen_path(citizen), params: values

    expect(response).to redirect_to(citizen)
    expect(citizen.images.reload).to contain_exactly(portrait, reused)
  end

  it "uploads an Active Storage image and renders a portrait variant" do
    sign_in create(:voter, admin: true)
    get edit_citizen_path(citizen)
    form = Nokogiri::HTML(response.body).at_css("form[action='#{citizen_path(citizen)}']")
    expect(form["enctype"]).to eq("multipart/form-data")
    expect(form.at_css("fieldset[disabled] button").text).to eq("Generate portrait")
    expect(form.css("fieldset[disabled] option").size).to eq(4)

    upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/portrait.png"), "image/png")
    patch citizen_path(citizen), params: { citizen: { image_placements_attributes: [ { position: 0,
      image_attributes: { file: upload, alt_text: "A new uploaded portrait" } } ] } }
    expect(response).to redirect_to(citizen)
    stored = citizen.images.reload.find { it.file.attached? }
    expect(stored.file.blob.filename.to_s).to eq("portrait.png")
    get citizen_path(citizen)
    page = Nokogiri::HTML(response.body)
    uploaded = page.at_css("img[alt='A new uploaded portrait']")
    expect(uploaded["src"]).to include("/rails/active_storage/representations/")
  end
end
