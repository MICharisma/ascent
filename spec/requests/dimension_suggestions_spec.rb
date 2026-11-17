require "rails_helper"

# "Suggest for me" ranks a citizen's or policy's unrated qualities. The provider sees only the curated
# catalog, the record's public name and type, and how often this voter has chosen each quality, and
# nothing is written. A missing or failing provider falls back to the curated order.
RSpec.describe "Dimension suggestions", type: :request do
  let(:voter) { create(:voter, first_name: "Teodora", last_name: "Lindqvist", email: "teodora.lindqvist@example.com") }
  let(:citizen) { create(:citizen, first_name: "Marisol", middle_name: nil, last_name: "Okafor", bio: nil) }
  let(:policy) { create(:policy) }
  let(:received) { [] }

  around do |example|
    previous = Rails.configuration.x.shared_ratings.suggestion_provider
    example.run
  ensure
    Rails.configuration.x.shared_ratings.suggestion_provider = previous
  end

  def provide(keys)
    Rails.configuration.x.shared_ratings.suggestion_provider = lambda do |**input|
      received << input
      keys
    end
  end

  def suggest(path)
    post path, headers: { "Accept" => "application/json" }
    response.parsed_body
  end

  before { sign_in voter }

  it "ranks only unrated qualities, ignoring duplicates and keys outside the catalog" do
    create(:dimension_rating, :distrusted_candidate, voter: voter, rated: citizen)
    provide %w[ascent.citizen.competence ascent.citizen.competence ascent.policy.fairness ascent.citizen.trustworthiness ascent.citizen.familiarity]

    expect(suggest(citizen_dimension_rating_suggestions_path(citizen))).to eq(
      "suggestions" => [ { "key" => "ascent.citizen.competence", "label" => "Competence" }, { "key" => "ascent.citizen.familiarity", "label" => "Familiarity" } ],
      "source" => "ai"
    )
    expect(received.sole[:candidates].map { it[:key] }).to eq(%w[ascent.citizen.familiarity ascent.citizen.competence])
  end

  it "sends the catalog, the record's public name and the voter's own choice counts, and nothing else" do
    other_citizen = create(:citizen)
    create(:dimension_rating, :capable_candidate, voter: voter, rated: other_citizen, value: -73)
    create(:dimension_rating, :capable_candidate, voter: create(:voter), rated: other_citizen)
    create(:rating, voter: voter, candidacy: create(:candidacy, citizen: citizen), rating: 417)
    provide []

    suggest citizen_dimension_rating_suggestions_path(citizen)

    input = received.sole
    expect(input[:subject]).to eq(type: "Citizen", name: "Marisol Okafor")
    expect(input[:candidates].first).to eq(key: "ascent.citizen.familiarity", label: "Familiarity", question: "How well do you know this person?")
    expect(input[:preferences]).to eq([ { key: "ascent.citizen.competence", times_chosen: 1 } ])
    expect(input.to_json).not_to include("teodora", "-73", "417", voter.id.to_s.then { %("#{it}") })
  end

  it "falls back to the curated order when the provider is unavailable" do
    Rails.configuration.x.shared_ratings.suggestion_provider = ->(**) { raise SharedRatings::LLMProvider::Unavailable, "timeout" }

    expect(suggest(policy_dimension_rating_suggestions_path(policy))).to eq(
      "suggestions" => [ { "key" => "ascent.policy.effectiveness", "label" => "Effectiveness" }, { "key" => "ascent.policy.fairness", "label" => "Fairness" },
        { "key" => "ascent.policy.affects_me", "label" => "Affects me" } ],
      "source" => "curated"
    )
  end

  it "rechecks qualities the voter rated while the provider was answering" do
    Rails.configuration.x.shared_ratings.suggestion_provider = lambda do |**|
      create(:dimension_rating, :well_known_candidate, voter: voter, rated: citizen)
      %w[ascent.citizen.familiarity]
    end

    keys = suggest(citizen_dimension_rating_suggestions_path(citizen))["suggestions"].map { it["key"] }
    expect(keys).to eq(%w[ascent.citizen.trustworthiness ascent.citizen.competence])
  end

  it "skips the provider once every quality is rated and writes nothing" do
    Citizen.rating_dimensions.each { create(:dimension_rating, voter: voter, rated: citizen, dimension_key: it.key) }
    provide %w[ascent.citizen.familiarity]

    expect { suggest(citizen_dimension_rating_suggestions_path(citizen)) }.not_to change { [ DimensionRating.count, DimensionRatingRevision.count ] }
    expect(response.parsed_body).to eq("suggestions" => [], "source" => "curated")
    expect(received).to be_empty
  end

  it "uses the configured model when the app has no override" do
    Rails.configuration.x.shared_ratings.suggestion_provider = nil
    allow(SharedRatings::LLMProvider).to receive(:from_env).and_return(->(**) { %w[ascent.policy.affects_me] })

    expect(suggest(policy_dimension_rating_suggestions_path(policy))["suggestions"].first).to eq("key" => "ascent.policy.affects_me", "label" => "Affects me")
  end

  it "turns away a visitor who isn't signed in" do
    sign_out voter
    post citizen_dimension_rating_suggestions_path(citizen)

    expect(response).to redirect_to(new_voter_session_path)
  end
end
