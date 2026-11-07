# One account on one platform, such as a campaign's YouTube channel or a candidate's Instagram.
class Channel < ApplicationRecord
  PLATFORMS = %w[website youtube instagram tiktok x bluesky facebook threads other].freeze
  PLATFORM_LABELS = { "website" => "Website", "youtube" => "YouTube", "instagram" => "Instagram", "tiktok" => "TikTok",
    "x" => "X", "bluesky" => "Bluesky", "facebook" => "Facebook", "threads" => "Threads", "other" => "Other" }.freeze
  # Stored as each owner's base class, so a party is an Organization.
  OWNER_TYPES = %w[Citizen Organization Candidacy].freeze
  REVIEW_STATUSES = %w[pending approved rejected].freeze

  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :reviewed_by, class_name: "Voter", optional: true
  has_many :communications, dependent: :restrict_with_error

  validates :platform, inclusion: { in: PLATFORMS }
  validates :handle, presence: true, uniqueness: { scope: :platform }
  validates :owner_type, inclusion: { in: OWNER_TYPES }, allow_nil: true
  validates :official, inclusion: { in: [ true, false ] }
  validates :review_status, inclusion: { in: REVIEW_STATUSES }
  validates :url, format: { with: %r{\Ahttps?://\S+\z} }, allow_blank: true

  scope :official, -> { where(official: true).where.not(review_status: "rejected") }
  scope :pending_review, -> { where(review_status: "pending") }
  scope :approved, -> { where(review_status: "approved") }
  scope :rejected, -> { where(review_status: "rejected") }

  def approve!(reviewer)
    update!(official: true, review_status: "approved", reviewed_by: reviewer, reviewed_at: Time.current)
  end

  def reject!(reviewer)
    update!(official: false, review_status: "rejected", reviewed_by: reviewer, reviewed_at: Time.current)
  end

  def name
    "#{handle} on #{platform_label}"
  end

  def platform_label
    PLATFORM_LABELS.fetch(platform)
  end
end
