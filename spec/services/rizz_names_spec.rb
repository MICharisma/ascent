require "rails_helper"
require "rizz-client"

RSpec.describe RizzNames::Store do
  let(:citizen) { create(:citizen, first_name: "Marisol", last_name: "Vega") }
  let(:store) { described_class.new("referring") }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("RIZZ_SCOPE").and_return("ascent-test")
  end

  def key(citizen_id) = Rizz::Projection.key(RizzNames.reference(citizen_id))

  it "stores and reads names under UUID Citizen keys" do
    store.put(key(citizen.id), "state" => "current", "display_name" => "Marisol Vega")

    expect(store.get(key(citizen.id)).fetch("display_name")).to eq("Marisol Vega")
    expect(store.keys).to eq([ key(citizen.id) ])
  end

  it "skips Rizz bindings made with pre-UUID Citizen IDs" do
    expect { store.put(key(42), "state" => "current", "display_name" => "Stale") }.not_to change(RizzName, :count)
    expect(store.get(key(42))).to be_nil
    expect(store.delete(key(42))).to eq(0)
  end
end
