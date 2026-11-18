require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#umami_tracker" do
    before { allow(ENV).to receive(:[]).and_call_original }

    context "in an environment measured by Umami" do
      before do
        allow(ENV).to receive(:[]).with("UMAMI_SCRIPT_URL").and_return "https://statsbegin.ascent.ing/script.js"
        allow(ENV).to receive(:[]).with("UMAMI_WEBSITE_ID").and_return "ced54035-17ab-4bf4-ae24-e6991d8c1bc7"
        allow(ENV).to receive(:[]).with("UMAMI_DOMAINS").and_return "build.ascent.ing"
      end

      it "loads the tracker for that website" do
        tracker = Capybara.string(helper.umami_tracker).find("script", visible: :all)

        expect(tracker[:src]).to eq "https://statsbegin.ascent.ing/script.js"
        expect(tracker["data-website-id"]).to eq "ced54035-17ab-4bf4-ae24-e6991d8c1bc7"
        expect(tracker["data-domains"]).to eq "build.ascent.ing"
        expect(tracker["data-exclude-search"]).to eq "true"
        expect(tracker["data-exclude-hash"]).to eq "true"
        expect(tracker[:defer]).to be_present
      end
    end

    context "in an environment without a Umami website" do
      before { allow(ENV).to receive(:[]).with("UMAMI_WEBSITE_ID").and_return nil }

      it "renders nothing" do
        expect(helper.umami_tracker).to be_nil
      end
    end
  end
end
