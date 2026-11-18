require "rails_helper"
require "rizz-client"

RSpec.describe RizzCitizenSync do
  let(:citizen) { create(:citizen, first_name: "Marisol", middle_name: nil, last_name: "Vega", username: "vega_ms_2a", username_status: "provisional", entity_code: "CITIZEN-VEGA_MS_2A", fictional: false) }
  let(:client) { double("Rizz client") }
  let(:entity_id) { SecureRandom.uuid }
  let(:response) { { "entity_id" => entity_id, "version" => 1, "qualified_code" => "MIC-RZZ-VEGA" } }
  let(:sync) { described_class.new(client: client) }

  it "gives a restored earlier snapshot a fresh revision and then skips it when unchanged" do
    imports = []
    allow(client).to receive(:import_person) do |payload, idempotency_key:|
      imports << [ payload.deep_dup, idempotency_key ]
      response.merge("version" => imports.size)
    end
    expect(sync.call(citizen).state).to eq("synced")
    citizen.update!(first_name: "Maria")
    expect(sync.call(citizen).state).to eq("synced")
    citizen.update!(first_name: "Marisol")
    expect(sync.call(citizen).state).to eq("synced")
    expect(imports.map { it.first.fetch("source_revision") }.uniq.size).to eq(3)
    expect(imports.map(&:last).uniq.size).to eq(3)
    expect(imports.first.first.fetch("full_name")).to eq(imports.last.first.fetch("full_name"))
    expect { sync.call(citizen) }.not_to change(imports, :size)
  end

  it "retries a lost response with exactly the same revision, request and transport key" do
    requests = []
    allow(client).to receive(:import_person) do |payload, idempotency_key:|
      requests << [ payload.deep_dup, idempotency_key ]
      raise Rizz::Unavailable, "Response lost" if requests.size == 1
      response
    end
    expect(sync.call(citizen).state).to eq("failed")
    expect(sync.call(citizen.reload).state).to eq("synced")
    expect(requests.first).to eq(requests.last)
  end

  it "uses a new transport key when retrying an optimistic version conflict" do
    RizzSync.create!(citizen: citizen, state: "synced", rizz_entity_id: entity_id, rizz_code: "MIC-RZZ-VEGA", rizz_version: 1, source_revision: "earlier")
    requests = []
    allow(client).to receive(:entity).with(entity_id).and_return({ "version" => 2 })
    allow(client).to receive(:import_person) do |payload, idempotency_key:|
      requests << [ payload.deep_dup, idempotency_key ]
      raise Rizz::Error.new(409, { "error" => "conflict" }) if requests.size == 1
      response.merge("version" => 3)
    end
    expect(sync.call(citizen).state).to eq("synced")
    expect(requests.map { it.first.fetch("source_revision") }.uniq.size).to eq(1)
    expect(requests.map { it.first.fetch("expected_version") }).to eq([ 1, 2 ])
    expect(requests.map(&:last).uniq.size).to eq(2)
  end

  it "skips an unchanged Citizen still using a legacy content-only revision" do
    imports = []
    allow(client).to receive(:import_person) { |payload, **| imports << payload; response }
    sync.call(citizen)
    row = citizen.rizz_sync
    row.update!(source_revision: row.source_revision.split(":").first)
    expect { sync.call(citizen) }.not_to change(imports, :size)
  end

  it "replaces a failed legacy revision with a fresh generation" do
    imports = []
    allow(client).to receive(:import_person) { |payload, **| imports << payload; response }
    sync.call(citizen)
    row = citizen.rizz_sync
    digest = row.source_revision.split(":").first
    row.update!(state: "failed", source_revision: digest)
    expect(sync.call(citizen.reload).state).to eq("synced")
    expect(imports.last.fetch("source_revision")).to start_with("#{digest}:")
    expect(imports.last.fetch("source_revision")).not_to eq(imports.first.fetch("source_revision"))
  end

  it "preserves the legacy request key when an unbound import lost its response" do
    allow(client).to receive(:import_person).and_raise(Rizz::Unavailable, "Response lost")
    sync.call(citizen)
    row = citizen.rizz_sync
    digest = row.source_revision.split(":").first
    row.update!(source_revision: digest)
    expect(client).to receive(:import_person).with(hash_including("source_revision" => digest), idempotency_key: "citizen-#{citizen.id}-#{digest}").and_return(response)
    expect(sync.call(citizen.reload).state).to eq("synced")
  end

  it "keeps a pending legacy identity review under its existing revision" do
    allow(client).to receive(:import_person).and_raise(Rizz::Unavailable, "Response lost")
    sync.call(citizen)
    row = citizen.rizz_sync
    digest = row.source_revision.split(":").first
    review_id = SecureRandom.uuid
    row.update!(state: "review", source_revision: digest, review_id: review_id)
    expect(client).to receive(:import_person).with(hash_including("source_revision" => digest), idempotency_key: "citizen-#{citizen.id}-#{digest}")
      .and_return({ "status" => "review_required", "review_id" => review_id })
    expect(sync.call(citizen.reload).state).to eq("review")
    expect(citizen.rizz_sync.reload.review_id).to eq(review_id)
  end
end
