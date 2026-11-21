# frozen_string_literal: true

# Single-use, 60 second proof that a browser confirmed a local Voter for a claim
# operation, or finished onboarding a new one (then it points at the create handoff and
# the Voter does not exist until the exchange spends it). Only the SHA-256 digest of the
# receipt is stored.
class RizzClaimReceipt < ApplicationRecord
  LIFETIME = 60.seconds

  belongs_to :voter, optional: true
  belongs_to :handoff, class_name: "RizzClaimHandoff", foreign_key: :rizz_claim_handoff_id, optional: true

  validates :receipt_digest, :operation_id, :expires_at, presence: true

  def self.issue!(operation_id:, voter: nil, handoff: nil)
    receipt = SecureRandom.urlsafe_base64(32)
    create!(voter: voter, handoff: handoff, operation_id: operation_id, receipt_digest: RizzClaimHandoff.digest(receipt), expires_at: LIFETIME.from_now)
    receipt
  end

  def self.find_by_receipt(receipt)
    find_by(receipt_digest: RizzClaimHandoff.digest(receipt))
  end

  def usable?
    consumed_at.nil? && expires_at.future?
  end

  def consume!
    self.class.where(id: id, consumed_at: nil).where("expires_at > ?", Time.current).update_all(consumed_at: Time.current, updated_at: Time.current) == 1
  end
end
