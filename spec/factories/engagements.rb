FactoryBot.define do
  factory :engagement do
    # A voter saving an issue to read about later
    association :voter
    association :engageable, factory: :affordable_housing_issue
    kind { :bookmark }

    trait :favorite do
      kind { :favorite }
    end

    trait :following_a_candidacy do
      association :engageable, factory: :candidacy
      kind { :follow }
    end

    trait :hidden do
      kind { :hide }
    end
  end
end
