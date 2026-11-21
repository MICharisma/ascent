# frozen_string_literal: true

module RizzSignIn
  # Applies a verified logout token: each jti is processed once, and the binding adopts the Speaker's exact epoch
  # (never lowered, never invented) and is marked disconnected so Rizz-opened sessions end on their next request.
  # A logout whose epoch is not ahead of the binding's is stale (e.g. it predates a re-claim) and changes nothing.
  module BackchannelLogout
    module_function

    def call(claims)
      ApplicationRecord.transaction do
        RizzBackchannelLogoutEvent.create!(
          jti: claims["jti"],
          rizz_sub: claims["sub"],
          rizz_epoch: claims["rizz_epoch"],
          processed_at: Time.current
        )
        binding = VoterRizzBinding.lock.find_by(rizz_sub: claims["sub"])
        next unless binding && claims["rizz_epoch"] > binding.rizz_session_epoch

        binding.update!(rizz_session_epoch: claims["rizz_epoch"], status: "disconnected", disconnected_at: Time.current)
      end
    rescue ActiveRecord::RecordNotUnique
      nil # redelivered jti; already applied
    end
  end
end
