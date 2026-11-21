# frozen_string_literal: true

# Links one Voter to one Rizz subject. rizz_session_epoch only moves forward; a
# Rizz-opened session older than it (or any session once disconnected) is ended.
class VoterRizzBinding < ApplicationRecord
  STATUSES = %w[active disconnected].freeze

  belongs_to :voter

  before_validation :assign_connected_at, on: :create

  validates :rizz_sub, :operation_id, :connected_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :rizz_session_epoch, numericality: { only_integer: true, greater_than: 0 }

  scope :active, -> { where(status: "active") }

  def active?
    status == "active"
  end

  private

  def assign_connected_at
    self.connected_at ||= Time.current
  end
end
