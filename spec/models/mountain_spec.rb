require "rails_helper"

# A mountain's unsaved edits live in a server-side draft until the voter saves them. Saving publishes the
# draft into ratings and the baseline, archives what it replaces, and sorts the mountain into residents or
# visitors. Ratings change freely; a saved baseline changes at most five times a day per race.
RSpec.describe Mountain do
  include ActiveSupport::Testing::TimeHelpers
  include_context "Port Merritt ballot"

  let(:race) { create_race_for(office_in(port_merritt, "Mayor"), :active) }
  let(:ventura_quinn) { create(:candidacy, race: race, citizen: create(:citizen, first_name: "Marisol", last_name: "Ventura-Quinn")) }
  let(:lindqvist) { create(:candidacy, race: race, citizen: create(:citizen, first_name: "Theo", last_name: "Lindqvist")) }
  let(:okafor) { create(:candidacy, race: race, citizen: create(:citizen, first_name: "Dana", last_name: "Okafor")) }
  let(:mountain) { described_class.new(voter: voter, race: race) }

  before { [ ventura_quinn, lindqvist, okafor ] }

  it "starts untouched, with nothing to save" do
    expect(mountain.baseline).to eq(200)
    expect(mountain.progress).to eq("not_started")
    expect(mountain).not_to be_unsaved
    expect(VoterRaceBaseline.where(voter: voter, race: race)).to be_empty
  end

  it "uses and saves the default baseline when only ratings change" do
    mountain.revise_draft!(ratings: { ventura_quinn.id => "201", lindqvist.id => "200" }, baseline: "200")

    expect(mountain.approved_candidacies).to eq([ ventura_quinn ])
    expect(mountain.unsaved_changes[:baseline]).to be_nil
    mountain.save!

    expect(mountain.saved_baseline).to eq(200)
    expect(mountain.progress).to eq("saved")
  end

  it "preserves a saved baseline and a draft baseline of zero" do
    mountain.publish!(ratings: {}, baseline: 280)
    expect(mountain.baseline).to eq(280)

    mountain.revise_draft!(baseline: 0)
    expect(mountain.baseline).to eq(0)
    mountain.save!
    expect(mountain.baseline).to eq(0)
  end

  it "keeps dragged ratings in a draft that shows as started until saved" do
    mountain.revise_draft!(ratings: { ventura_quinn.id => "410", lindqvist.id => "120" }, baseline: "280")

    expect(MountainDraft.find_by!(voter: voter, race: race).ratings).to eq(ventura_quinn.id.to_s => 410, lindqvist.id.to_s => 120)
    expect(Rating.where(voter: voter)).to be_empty
    expect(mountain.progress).to eq("started")
    expect(mountain.unsaved_changes).to eq(candidacy_ids: [ ventura_quinn.id, lindqvist.id ], baseline: [ 200, 280 ])
    expect(mountain.approved_candidacies).to eq([ ventura_quinn ])
  end

  it "publishes the draft on save, counting a resident's mountain with residents" do
    mountain.revise_draft!(ratings: { ventura_quinn.id => 410, lindqvist.id => 120, okafor.id => 360 }, baseline: 280)
    mountain.save!

    expect(MountainDraft.count).to eq(0)
    expect(Rating.where(voter: voter).pluck(:candidacy_id, :rating)).to contain_exactly([ ventura_quinn.id, 410 ], [ lindqvist.id, 120 ], [ okafor.id, 360 ])
    expect(VoterRaceBaseline.find_by!(voter: voter, race: race)).to have_attributes(baseline: 280, counted_as: "resident")
    expect(mountain.progress).to eq("saved")
    expect(mountain.approved_candidacies).to eq([ ventura_quinn, okafor ])
  end

  it "counts a pretend vote with visitors" do
    visitor = create(:voter, first_name: "Omar", last_name: "Haddad")

    described_class.new(voter: visitor, race: race).publish!(ratings: { okafor.id => 300 }, baseline: 200)

    expect(VoterRaceBaseline.find_by!(voter: visitor)).to be_visitor
  end

  it "drops the draft once dragging returns everything to what is saved" do
    mountain.publish!(ratings: { ventura_quinn.id => 410 }, baseline: 280)

    mountain.revise_draft!(ratings: { ventura_quinn.id => 300 })
    expect(mountain).to be_unsaved
    mountain.revise_draft!(ratings: { ventura_quinn.id => 410 })

    expect(mountain).not_to be_unsaved
    expect(MountainDraft.count).to eq(0)
  end

  it "removes a saved rating the draft blanks, and archives the one it changes" do
    mountain.publish!(ratings: { ventura_quinn.id => 410, lindqvist.id => 120 }, baseline: 280)

    mountain.revise_draft!(ratings: { ventura_quinn.id => 350, lindqvist.id => "" })
    mountain.save!

    expect(Rating.where(voter: voter).pluck(:candidacy_id, :rating)).to eq([ [ ventura_quinn.id, 350 ] ])
    expect(RatingArchive.where(voter: voter, candidacy: ventura_quinn).pluck(:rating)).to eq([ 410 ])
  end

  it "discards unsaved edits without touching the saved mountain" do
    mountain.publish!(ratings: { ventura_quinn.id => 410 }, baseline: 280)
    mountain.revise_draft!(baseline: 450)

    mountain.discard!

    expect(mountain.baseline).to eq(280)
    expect(mountain.progress).to eq("saved")
  end

  it "refuses a draft rating for a candidate who is not on this voter's mountain" do
    elsewhere = create(:candidacy)

    expect { mountain.revise_draft!(ratings: { elsewhere.id => 300 }) }.to raise_error(ActiveRecord::RecordInvalid, /not on this mountain/)
  end

  it "allows five baseline changes a day, then refuses the sixth but still saves ratings" do
    mountain.publish!(ratings: { ventura_quinn.id => 410 }, baseline: 200)
    5.times { |change| mountain.publish!(ratings: {}, baseline: 210 + change * 10) }

    expect(mountain.baseline_changes_left_today).to eq(0)
    expect { mountain.publish!(ratings: {}, baseline: 400) }.to raise_error(ActiveRecord::RecordInvalid, /5 times a day/)
    expect { mountain.publish!(ratings: { lindqvist.id => 250 }, baseline: 250) }.to change(Rating, :count).by(1)

    travel_to 1.day.from_now do
      expect(described_class.new(voter: voter, race: race).baseline_changes_left_today).to eq(5)
    end
  end
end
