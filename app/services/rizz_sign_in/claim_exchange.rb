# frozen_string_literal: true

module RizzSignIn
  # Server-to-server step of a claim or create: spend the browser's receipt and bind the Voter to the Rizz subject.
  # A create receipt also builds the Voter from its onboarded handoff, in the same transaction.
  # Repeating an operation_id for the same subject and receipt returns the same success.
  class ClaimExchange
    Result = Struct.new(:status, :voter)
    Conflict = Class.new(StandardError)
    EmailTaken = Class.new(Conflict)

    def self.call(**args)
      new(**args).call
    end

    def initialize(operation_id:, receipt:, rizz_sub:, rizz_session_epoch:)
      @operation_id = operation_id
      @receipt = receipt
      @rizz_sub = rizz_sub
      @epoch = rizz_session_epoch
    end

    # status: :ok, :invalid (bad or spent receipt), :conflict (already bound elsewhere, or the new Voter's handle is taken),
    # :email_taken (a create receipt's email or Google account now belongs to a Voter)
    def call
      ApplicationRecord.transaction { bind }
    rescue ActiveRecord::RecordNotUnique
      replay
    rescue EmailTaken
      Result.new(:email_taken)
    rescue Conflict
      Result.new(:conflict)
    end

    private

    def bind
      return replay if VoterRizzBinding.exists?(operation_id: @operation_id)

      receipt = RizzClaimReceipt.find_by_receipt(@receipt)
      return invalid_or_replay unless receipt&.usable? && receipt.operation_id == @operation_id

      voter = receipt.voter || new_voter_for(receipt)
      return Result.new(:invalid) unless voter&.active_for_authentication?

      by_sub = VoterRizzBinding.lock.find_by(rizz_sub: @rizz_sub)
      held = VoterRizzBinding.lock.active.find_by(voter_id: voter.id) if voter.persisted?
      return Result.new(:conflict) if (held && held.rizz_sub != @rizz_sub) || (by_sub&.active? && by_sub.voter_id != voter.id)
      return invalid_or_replay unless receipt.consume!

      create_voter!(voter, receipt) unless voter.persisted?

      attributes = { voter: voter, operation_id: @operation_id, status: "active", connected_at: Time.current, disconnected_at: nil }
      if by_sub
        by_sub.update!(attributes.merge(rizz_session_epoch: [ by_sub.rizz_session_epoch, @epoch ].max))
      else
        VoterRizzBinding.create!(attributes.merge(rizz_sub: @rizz_sub, rizz_session_epoch: @epoch))
      end
      Result.new(:ok, voter)
    end

    # The unsaved Voter a create receipt stands for, once its handoff still holds the onboarded password.
    def new_voter_for(receipt)
      handoff = receipt.handoff
      return unless handoff&.create_intent? && handoff.encrypted_password.present?

      handoff.build_voter
    end

    # Email, handle or Google account taken since onboarding: nothing is created or linked, and the whole transaction
    # rolls back. A Google account that now belongs to a Voter is reported like a taken email.
    def create_voter!(voter, receipt)
      voter.transaction(requires_new: true) { voter.save! }
      receipt.handoff.discard_draft!
    rescue ActiveRecord::RecordInvalid => error
      errors = error.record.errors
      raise(errors.of_kind?(:email, :taken) || errors.of_kind?(:uid, :taken) ? EmailTaken : Conflict)
    rescue ActiveRecord::RecordNotUnique
      raise(Voter.exists?(email: voter.email) || (voter.uid.present? && Voter.find_by_google_uid(voter.uid).present?) ? EmailTaken : Conflict)
    end

    def replay
      binding = VoterRizzBinding.active.find_by(operation_id: @operation_id)
      return Result.new(:conflict) unless binding&.rizz_sub == @rizz_sub
      return Result.new(:invalid) unless RizzClaimReceipt.find_by_receipt(@receipt)&.operation_id == @operation_id

      Result.new(:ok, binding.voter)
    end

    def invalid_or_replay
      VoterRizzBinding.exists?(operation_id: @operation_id) ? replay : Result.new(:invalid)
    end
  end
end
