require "rails_helper"

# Quality ratings use each model's curated catalog on the shared standard scale,
# and every change leaves a revision with the definition in force at the time.
RSpec.describe DimensionRating do
  let(:voter) { create(:voter, first_name: "Odette", last_name: "Marchetti") }
  let(:citizen) { create(:citizen, first_name: "Renata", middle_name: nil, last_name: "Vasquez-Holm") }

  def error_attributes(rating)
    rating.validate
    rating.errors.attribute_names
  end

  it "offers the agreed citizen and policy qualities" do
    expect(Citizen.rating_dimensions.map(&:key)).to eq(%w[ascent.citizen.familiarity ascent.citizen.trustworthiness ascent.citizen.competence])
    expect(Policy.rating_dimensions.map(&:key)).to eq(%w[ascent.policy.effectiveness ascent.policy.fairness ascent.policy.affects_me])
    expect(Citizen.rating_dimensions.map { [ it.minimum, it.maximum, it.neutral_value, it.coarse_step, it.fine_step ] }.uniq)
      .to eq([ [ -100, 500, 0, 10, 1 ] ])
  end

  it "accepts both endpoints and an explicit neutral zero" do
    [ -100, 0, 500, 137 ].each do |value|
      expect(build(:dimension_rating, voter: voter, rated: citizen, value: value)).to be_valid
    end
  end

  it "rejects scores off the scale, missing scores and another model's qualities" do
    expect(build(:dimension_rating, voter: voter, rated: citizen, value: 501).then { error_attributes(it) }).to include(:value)
    expect(build(:dimension_rating, voter: voter, rated: citizen, value: -101).then { error_attributes(it) }).to include(:value)
    expect(build(:dimension_rating, voter: voter, rated: citizen, value: nil).then { error_attributes(it) }).to include(:value)
    expect(build(:dimension_rating, voter: voter, rated: citizen, dimension_key: "ascent.policy.fairness").then { error_attributes(it) }).to include(:dimension_key)
  end

  it "records rating, changing and clearing as revisions with the definition used" do
    rating = create(:dimension_rating, :distrusted_candidate, voter: voter, rated: citizen)
    rating.update!(value: 40)
    rating.update!(updated_at: 1.minute.from_now)
    rating.destroy!

    revisions = voter.dimension_rating_revisions.order(:id)
    expect(revisions.pluck(:event, :value)).to eq([ [ "rate", -80 ], [ "change", 40 ], [ "clear", 40 ] ])
    expect(revisions.first.definition).to include("key" => "ascent.citizen.trustworthiness", "version" => 1, "minimum" => -100, "maximum" => 500)
    expect(revisions.first).to have_attributes(rated_type: "Citizen", rated_id: citizen.id)
  end

  it "keeps a voter's history when the citizen is removed, and removes it with the voter" do
    create(:dimension_rating, :capable_candidate, voter: voter, rated: citizen)
    citizen.destroy!

    expect(described_class.count).to eq(0)
    expect(voter.dimension_rating_revisions.pluck(:event)).to eq([ "rate" ])

    voter.destroy!
    expect(DimensionRatingRevision.count).to eq(0)
  end

  it "averages every voter's rating of one quality" do
    create(:dimension_rating, :well_known_candidate, rated: citizen)
    create(:dimension_rating, :neutral, rated: citizen)
    create(:dimension_rating, :distrusted_candidate, rated: citizen)

    count, average = citizen.voters_average_on(Citizen.rating_dimension_for("ascent.citizen.familiarity"))
    expect([ count, average.to_f ]).to eq([ 2, 210.0 ])
  end
end
