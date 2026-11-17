# frozen_string_literal: true

# Any signed-in voter can rate qualities and ask for suggestions; the controller only ever reaches
# that voter's own ratings.
class DimensionRatingPolicy < ApplicationPolicy
  def create?
    voter.present?
  end

  def destroy?
    voter.present?
  end

  def suggest?
    voter.present?
  end
end
