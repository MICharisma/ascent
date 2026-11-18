# How far RizzNames has read Rizz's event feed, per display purpose.
class RizzFeedCursor < ApplicationRecord
  validates :purpose, inclusion: { in: RizzName::PURPOSES }, uniqueness: true
end
