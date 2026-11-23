# frozen_string_literal: true

# Any signed-in voter can mark records; only the voter who made a mark can remove it.
class EngagementPolicy < ApplicationPolicy
  def index?
    signed_in?
  end

  def create?
    signed_in?
  end

  def destroy?
    signed_in? && record.voter_id == voter.id
  end

  private

  def signed_in?
    voter.present?
  end
end
