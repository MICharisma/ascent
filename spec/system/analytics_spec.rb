require "rails_helper"

# Analytics depend on Turbo visits, the share sheet and the clipboard, and the
# mountain editor animates with GSAP, which never settles in jsdom, so these
# stay in Chrome.
RSpec.describe "Browser analytics", type: :system do
  let(:voter) { create(:voter, first_name: "Rosa", last_name: "Delgado") }
  let(:race) { create(:race, :active) }
  let!(:candidate) { create(:candidacy, race: race) }

  def browser_events(name)
    page.evaluate_script("window.analyticsEvents.filter(event => event.name === #{name.to_json})")
  end

  def expect_browser_event_count(name, count)
    expect(page).to have_css("html", visible: :all, wait: 5) { browser_events(name).size == count }
  end

  def capture_events
    expect(page).to have_css("html", visible: :all) do
      page.evaluate_script('import("analytics").then(module => Boolean(module.pageAnalytics.context))')
    end
    page.execute_script <<~JS
      window.analyticsEvents = []
      const originalTrack = window.ahoy.track.bind(window.ahoy)
      window.ahoy.track = (name, properties) => {
        window.analyticsEvents.push({ name, properties })
        return originalTrack(name, properties)
      }
    JS
  end

  it "persists one page view per Turbo visit and tracks navigation and engagement" do
    visit root_path
    expect(page).to have_css('meta[name="ascent-analytics"]', visible: false)
    expect(page).to have_link("About Approval Voting")
    capture_events
    find('a[href="/approval-voting"]', match: :first).click
    expect(page).to have_current_path(approval_voting_path)
    expect(page).to have_link("Try a Mountain")

    expect_browser_event_count("page_viewed", 1)
    expect(browser_events("navigation_used").size).to eq(1)
    expect(browser_events("page_engaged").size).to eq(1)
    expect(browser_events("page_viewed").first.fetch("properties")).to include("previous_path" => "/", "page_type" => "pages.approval_voting")
    expect(Ahoy::Event.where(name: "page_viewed").count).to be >= 1
  end

  it "records a completed slider adjustment once and leaves the ranking usable" do
    sign_in voter
    visit edit_mountain_path(race)
    expect(page).to have_css(".mountain-page")
    capture_events
    page.execute_script <<~JS
      const slider = document.querySelector('[data-role="rating-slider"]')
      slider.value = 350
      slider.dispatchEvent(new Event("input", { bubbles: true }))
      slider.value = 400
      slider.dispatchEvent(new Event("input", { bubbles: true }))
    JS
    expect(browser_events("rating_changed")).to be_empty
    page.execute_script <<~JS
      document.querySelector('[data-role="rating-slider"]').dispatchEvent(new Event("change", { bubbles: true }))
    JS
    expect(browser_events("rating_changed").size).to eq(1)
    expect(browser_events("rating_changed").first.fetch("properties")).to include("input_method" => "slider", "rated_count" => 1, "race_id" => race.id)
    find('button[aria-label="Raise baseline by 10"]').click
    expect(browser_events("baseline_changed").size).to eq(1)
    expect(page).to have_button("Save mountain")
    click_button "Save mountain"
    expect(page).to have_button("Saved", disabled: true)
    expect(Rating.find_by!(voter: voter, candidacy: candidate).rating).to eq(400)
    expect(Ahoy::Event.where(name: "mountain_save").map { it.properties["outcome"] }).to eq(%w[attempted succeeded])
  end

  it "tracks successful copies and cancelled share sheets without counting cancellation as delivery" do
    sign_in voter
    visit edit_voter_path(voter)
    expect(page).to have_button("Share invite link")
    capture_events
    page.execute_script <<~JS
      Object.defineProperty(navigator, "share", { configurable: true, value: undefined })
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: async url => { window.copiedInvite = url } } })
    JS
    click_button "Share invite link"
    expect(page).to have_content("Link copied")
    expect(browser_events("share_action").map { it.fetch("properties").fetch("outcome") }).to eq(%w[attempted copied])
    copied = page.evaluate_script("window.copiedInvite")
    expect(copied).to match(%r{/invite/#{voter.invite_token}\?ref=[0-9a-f]{32}\z})

    page.execute_script <<~JS
      Object.defineProperty(navigator, "share", { configurable: true, value: async () => { throw new DOMException("Cancelled", "AbortError") } })
    JS
    click_button "Share invite link"
    expect(browser_events("share_action").map { it.fetch("properties").fetch("outcome") }).to eq(%w[attempted copied attempted cancelled])
  end

  it "reports filtered result counts, including empty results" do
    visit races_path
    capture_events
    find('input[name="q"]').set("No matching mountain race")
    click_button "Apply"
    expect(page).to have_content("No races match")

    expect_browser_event_count("browse_refined", 1)
    browse = browser_events("browse_refined").last.fetch("properties")
    expect(browse).to include("filter_names" => [ "q" ], "result_count" => 0, "query_length" => "No matching mountain race".length)
    expect(browse).not_to have_key("query")
  end

  it "counts a promoted result-frame visit once, without counting lazy candidate cards" do
    create_list(:race, 25, :active, election: race.election)
    visit races_path
    capture_events
    find('a[aria-label="Next page"]').click
    expect(page).to have_current_path(races_path(page: 2))
    expect(page).to have_css("html:not([aria-busy])")
    expect_browser_event_count("page_viewed", 1)
    expect(browser_events("page_viewed").sole.fetch("properties")).to include("frame_id" => "races-list", "path" => "/races")

    page.execute_script <<~JS
      const frame = document.createElement("turbo-frame")
      frame.id = "candidate-card"
      document.body.append(frame)
      frame.dispatchEvent(new CustomEvent("turbo:frame-load", { bubbles: true }))
    JS
    expect(browser_events("page_viewed").size).to eq(1)
  end
end
