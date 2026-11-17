class Policy < ApplicationRecord
  include Titled
  include DimensionRated

  rating_dimension :effectiveness, question: "Will this policy achieve its aim?", low_label: "Ineffective", high_label: "Very effective"
  rating_dimension :fairness, question: "How fair is this policy to the people it affects?", low_label: "Unfair", high_label: "Very fair"
  rating_dimension :affects_me, question: "How much does this policy affect you personally?", low_label: "Not at all", high_label: "A great deal"

  belongs_to :governing_body
  belongs_to :area_of_concern
  belongs_to :approach
  has_many :official_codes

  # The status column stores these words, so the enum maps each value to itself.
  enum :status, { pending: "pending", enacted: "enacted", repealed: "repealed" }, validate: true


  scope :by_governing_body, ->(governing_body_id) { where(governing_body_id: governing_body_id) if governing_body_id.present? }
end
