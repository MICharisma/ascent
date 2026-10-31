require 'rails_helper'

RSpec.describe "Pages", type: :request do
  describe "GET /" do
    it "renders the project overview" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Elections without spoiled plans")
      expect(response.body).to include("For Philanthropic Partners")
      expect(response.body).to include("About Approval Voting")
      expect(response.body).to include("Expressive Voting turns elections into a collaboration.")
    end

    it "shows active race previews when data exists" do
      race = create(:race, :active)
      election = race.election
      election.update!(description: "A model election for the landing page.")

      get root_path

      expect(response.body).to include(election.name)
      expect(response.body).to include("Open Mountain")
    end
  end

  describe "GET /supporters" do
    it "renders the philanthropic overview page" do
      get supporters_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ascent is building public-interest infrastructure for studying better ballots and clearer governance.")
      expect(response.body).to include("The value proposition is civic capacity, not party advantage.")
      expect(response.body).to include("What support could fund next")
    end
  end

  describe "GET /glossary" do
    it "renders the schema glossary page" do
      get glossary_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("How the current data model names the civic concepts in Ascent.")
      expect(response.body).to include("Each position belongs to a branch: legislative, executive, or judicial.")
      expect(response.body).to include("An office can also sit in a GoverningBody")
      expect(response.body).to include("A voter&#39;s approval threshold for one race.")
      expect(response.body).to include("Separate namespace from the general Topic model.")
    end
  end

  describe "GET /faq" do
    it "renders the seed data FAQ with the playground contribution example" do
      get faq_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("How Ascent&#39;s public seed repository works")
      expect(response.body).to include("What is the seeds repository?")
      expect(response.body).to include("How do I submit data through a pull request?")
      expect(response.body).to include("playgrounds_once_per_decade.yml")
      expect(response.body).to include("TOPIC-PARKS_AND_PLAY")
      expect(response.body).to include("Build One New Playground Per Decade")
      expect(response.body).to include("CANDIDACY-USA-NY-EXAMPLE-ED_1-2026_GENERAL-EXAMPLE_AV_7K")
      expect(response.body).to include(%(href="https://github.com/MICharisma/ascent_seed_data"))
    end
  end

  describe "GET /approval-voting" do
    it "renders the case for approval voting from the content file" do
      get approval_voting_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Approval Voting means you can vote for as many candidates as you like.")
      expect(response.body).to include("The spoiler effect")
      expect(response.body).to include("Approval voting is almost embarrassingly simple.")
      expect(response.body).to include("This is a working thesis, not a finished proof.")
    end
  end

  describe "GET /terms-of-service" do
    it "renders the MICharisma Inc. terms of service and includes a footer link" do
      get terms_of_service_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Terms of Service")
      expect(response.body).to include("MICharisma Inc.")
      expect(response.body).to include("European Union (EU)")
      expect(response.body).to include(%(href="#{terms_of_service_path}"))
    end
  end

  describe "error pages" do
    around do |example|
      show_exceptions = Rails.application.env_config["action_dispatch.show_exceptions"]
      detailed = Rails.application.env_config["action_dispatch.show_detailed_exceptions"]
      Rails.application.env_config["action_dispatch.show_exceptions"] = :all
      Rails.application.env_config["action_dispatch.show_detailed_exceptions"] = false
      example.run
    ensure
      Rails.application.env_config["action_dispatch.show_exceptions"] = show_exceptions
      Rails.application.env_config["action_dispatch.show_detailed_exceptions"] = detailed
    end

    it "renders the branded not-found page for unknown routes" do
      get "/this-ascent-path-does-not-exist"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("This trail does not lead to a page.")
      expect(response.body).to include("Return to Overview")
    end

    it "renders the branded internal error page when a controller raises" do
      allow_any_instance_of(PagesController).to receive(:home).and_raise(StandardError, "forced error page")

      get root_path

      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("Ascent hit an unexpected fault.")
      expect(response.body).to include("Browse Elections")
    end
  end
end

