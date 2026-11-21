# frozen_string_literal: true

require "rails_helper"

RSpec.describe VoterRizzBinding, type: :model do
  let(:voter) { create(:voter) }

  def bind(voter: self.voter, sub: "sub-#{SecureRandom.hex(4)}", operation: "op-#{SecureRandom.hex(4)}", **attributes)
    described_class.create!(voter: voter, rizz_sub: sub, operation_id: operation, **attributes)
  end

  it "gets a UUIDv7 id and starts active at epoch 1" do
    binding = bind
    expect(binding.id).to match(/\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/)
    expect(binding).to have_attributes(status: "active", rizz_session_epoch: 1)
    expect(binding.connected_at).to be_present
    expect(voter.reload.active_rizz_binding).to eq(binding)
    expect(voter.rizz_bindings).to contain_exactly(binding)
  end

  it "allows only one active binding per Voter but any number of disconnected ones" do
    bind
    expect { bind }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { bind(status: "disconnected") }.not_to raise_error
    expect { bind(status: "disconnected") }.not_to raise_error
  end

  it "keeps rizz_sub and operation_id unique" do
    bind(sub: "same")
    expect { bind(voter: create(:voter), sub: "same") }.to raise_error(ActiveRecord::RecordNotUnique)
    first = described_class.last
    expect { bind(voter: create(:voter), operation: first.operation_id) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects an unknown status and non-positive epoch in model and database" do
    expect { bind(status: "pending") }.to raise_error(ActiveRecord::RecordInvalid)
    expect {
      described_class.new(voter: voter, rizz_sub: "x", operation_id: "y", status: "active", connected_at: Time.current)
        .tap { it.status = "bogus" }
        .save!(validate: false)
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect { bind(rizz_session_epoch: 0) }.to raise_error(ActiveRecord::RecordInvalid)
    expect {
      described_class.new(voter: voter, rizz_sub: "x2", operation_id: "y2", status: "active", connected_at: Time.current)
        .tap { it.rizz_session_epoch = 0 }
        .save!(validate: false)
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "splits RizzClaimHandoff#suggested_name_parts cleanly" do
    expect(RizzClaimHandoff.new(display_name: "Marcus Tate").suggested_name_parts).to eq([ "Marcus", "Tate" ])
    expect(RizzClaimHandoff.new(display_name: "  Mary   Jane Watson ").suggested_name_parts).to eq([ "Mary", "Jane Watson" ])
    expect(RizzClaimHandoff.new(display_name: "Cher").suggested_name_parts).to eq([ "Cher", "" ])
    expect(RizzClaimHandoff.new(display_name: "   ").suggested_name_parts).to eq([ "", "" ])
    expect(RizzClaimHandoff.new(display_name: nil).suggested_name_parts).to eq([ "", "" ])
  end
end
