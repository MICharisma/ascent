class Issue < ApplicationRecord
  include Engageable
  include Titled

  belongs_to :topic
  has_many :approaches
  has_many :stances, through: :approaches


  scope :by_topic, ->(topic_id) { where(topic_id: topic_id) if topic_id.present? }
end
