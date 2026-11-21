# frozen_string_literal: true

module RizzSignIn
  # Browser step of creating an account from Rizz: validate the chosen name, username, display name and optional
  # password against the verified handoff's email, then spend the handoff and issue the receipt in one transaction.
  # No Voter is saved here. The Speaker's server-to-server exchange builds it after its own cookie-bound check.
  class Onboarding
    Result = Struct.new(:status, :voter, :receipt)

    def self.call(**args)
      new(**args).call
    end

    def initialize(handoff:, attributes:)
      @handoff = handoff
      @attributes = attributes
    end

    # status: :onboarded (receipt issued), :invalid (voter carries the errors), :existing_email (handoff continues
    # as a claim), :gone (expired, spent or no longer a create handoff)
    def call
      RizzClaimHandoff.transaction(requires_new: true) { onboard } || Result.new(:gone)
    end

    private

    def onboard
      @handoff.lock!
      return Result.new(:existing_email) if @handoff.claim_intent? && @handoff.usable?
      return Result.new(:gone) unless @handoff.usable? && RizzSignIn.configuration.issuer_origin?(@handoff.callback_uri)

      voter = Voter.new(@attributes.merge(password_attributes).merge(email: @handoff.email, **google_attributes))
      voter.skip_confirmation!
      voter.valid?
      voter.errors.add(:username, :blank) if voter.username.blank?
      voter.errors.add(:display_name, :blank) if voter.display_name.blank?
      return rejected(voter) if voter.errors.any?

      @handoff.onboard!(voter)
      @handoff.consume! or raise ActiveRecord::Rollback
      Result.new(:onboarded, voter, RizzClaimReceipt.issue!(handoff: @handoff, operation_id: @handoff.operation_id))
    end

    # Leaving both password fields blank is a passwordless 1-click create: the Voter gets a random internal password
    # (the owner can sign in with Google or Rizz, or reset it by email). Typing into either field runs normal validation.
    def password_attributes
      password = @attributes["password"].to_s
      confirmation = @attributes["password_confirmation"].to_s
      return { "password" => password, "password_confirmation" => confirmation } unless password.empty? && confirmation.empty?

      generated = Devise.friendly_token(32)
      { "password" => generated, "password_confirmation" => generated }
    end

    def google_attributes
      @handoff.google_uid.present? ? { provider: "google_oauth2", uid: @handoff.google_uid } : {}
    end

    def rejected(voter)
      return Result.new(:invalid, voter) unless voter.errors.of_kind?(:email, :taken) || voter.errors.of_kind?(:uid, :taken)

      @handoff.switch_to_claim!
      Result.new(:existing_email)
    end
  end
end
