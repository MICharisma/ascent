# System specs exist for layout: what only a real browser's CSS can show.
# Behavior belongs in interaction specs (spec/interactions).
module LayoutHelpers
  def phone_viewport
    page.driver.browser.execute_cdp "Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: false
  end

  def expect_no_horizontal_overflow
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true), "#{page.current_path} scrolls sideways"
  end

  # Visits each page, in light and dark themes, and checks it fits the viewport.
  def expect_pages_to_fit(*paths)
    paths.each do |path|
      visit path
      expect(page).to have_current_path(path.split("?").first, ignore_query: true)
      %w[light dark].each do |theme|
        page.execute_script("document.documentElement.dataset.theme = arguments[0]", theme)
        expect_no_horizontal_overflow
      end
    end
  end

  def rect(selector)
    page.evaluate_script("document.querySelector(arguments[0]).getBoundingClientRect().toJSON()", selector)
  end
end

require "capybara/rspec"

Capybara.server = :puma, { Silent: true }

RSpec.configure do |config|
  config.before(type: :system) { driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 1000 ] }
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include LayoutHelpers, type: :system
  config.after(type: :system) do
    page.driver.browser.execute_cdp "Emulation.clearDeviceMetricsOverride" if page.driver.browser.respond_to?(:execute_cdp)
  end
end
