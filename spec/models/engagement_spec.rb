require 'rails_helper'

RSpec.describe Engagement, type: :model do
  let(:voter) { create(:voter, first_name: "Priya", last_name: "Raman", email: "priya.raman@example.com") }

  it "only marks the kinds of records visitors can engage with" do
    engagement = build(:engagement, voter: voter, engageable: create(:topic))

    expect(engagement).not_to be_valid
    expect(engagement.errors[:engageable_type]).to be_present
  end

  it "keeps a voter to one mark of each kind per record" do
    issue = create(:affordable_housing_issue)
    create(:engagement, voter: voter, engageable: issue, kind: :follow)

    expect(build(:engagement, voter: voter, engageable: issue, kind: :follow)).not_to be_valid
    expect(build(:engagement, voter: voter, engageable: issue, kind: :favorite)).to be_valid
  end

  describe EngagementSummary do
    it "loads a page's marks and public counts in two queries" do
      issues = create_list(:issue, 3)
      neighbor = create(:voter)
      create(:engagement, voter: voter, engageable: issues.first, kind: :bookmark)
      create(:engagement, voter: neighbor, engageable: issues.first, kind: :favorite)
      create(:engagement, voter: neighbor, engageable: issues.last, kind: :bookmark)
      summary = described_class.new(issues, voter)

      queries = []
      counter = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        issues.each { |issue| Engagement.kinds.each_key { |kind| summary.marked?(issue, kind) && summary.count(issue, kind) } }
      end

      expect(queries.size).to eq(2)
      expect(summary.marked?(issues.first, :bookmark)).to be(true)
      expect(summary.count(issues.first, :favorite)).to eq(1)
      expect(summary.count(issues.last, :bookmark)).to eq(0)
    end
  end
end
