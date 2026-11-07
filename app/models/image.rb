class Image < ApplicationRecord
  WEB_ADDRESS = %r{\Ahttps?://\S+\z}
  CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_FILE_SIZE = 10.megabytes

  has_one_attached :file do |attachment|
    attachment.variant :avatar, resize_to_fill: [ 96, 96 ]
    attachment.variant :thumbnail, resize_to_limit: [ 320, 320 ]
    attachment.variant :portrait, resize_to_fill: [ 800, 1000 ]
    attachment.variant :large, resize_to_limit: [ 1600, 1600 ]
  end

  has_many :image_placements, dependent: :restrict_with_error
  has_many :citizens, through: :image_placements, source: :subject, source_type: "Citizen"
  has_many :candidacies, through: :image_placements, source: :subject, source_type: "Candidacy"

  normalizes :url, with: -> { it.presence }
  validates :url, uniqueness: true, format: { with: WEB_ADDRESS }, allow_blank: true
  validates :source_url, format: { with: WEB_ADDRESS }, allow_blank: true
  validate :image_content

  def name
    alt_text.presence || url.presence || file.filename.to_s
  end

  def ai_generated?
    file.attached? && file.blob.metadata["ai_generated"] == true
  end

  private

  def image_content
    errors.add(:base, "Upload an image or provide its original image URL") unless file.attached? || url.present?
    return unless file.attached?

    errors.add(:file, "must be a JPEG, PNG, or WebP image") unless CONTENT_TYPES.include?(file.content_type)
    errors.add(:file, "must be 10 MB or smaller") if file.byte_size > MAX_FILE_SIZE
  end
end
