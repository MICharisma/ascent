# frozen_string_literal: true

# Remembers each processed logout token jti so redelivery is a no-op.
class RizzBackchannelLogoutEvent < ApplicationRecord
  validates :jti, :rizz_sub, :rizz_epoch, :processed_at, presence: true
end
