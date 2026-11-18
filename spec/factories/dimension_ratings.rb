FactoryBot.define do
  # A voter's score for one curated quality of a citizen or a policy, on the shared −100 to +500 scale.
  # Zero is neutral; −100 is the strongest negative and +500 the strongest positive.
  factory :dimension_rating do
    association :voter
    association :rated, factory: :citizen
    dimension_key { "ascent.citizen.familiarity" }
    value { 180 }

    # A voter who has followed this candidate's campaigns closely for years.
    trait :well_known_candidate do
      dimension_key { "ascent.citizen.familiarity" }
      value { 420 }
    end

    # A voter who has caught this candidate breaking promises and says so.
    trait :distrusted_candidate do
      dimension_key { "ascent.citizen.trustworthiness" }
      value { -80 }
    end

    # A voter who thinks this candidate would run an office well, whatever their politics.
    trait :capable_candidate do
      dimension_key { "ascent.citizen.competence" }
      value { 310 }
    end

    # A voter who explicitly chose neutral rather than leaving the quality unrated.
    trait :neutral do
      value { 0 }
    end

    # A renter who expects the housing standards to add real affordable units.
    trait :effective_housing_policy do
      association :rated, factory: :policy
      dimension_key { "ascent.policy.effectiveness" }
      value { 260 }
    end

    # A small landlord who feels the policy's costs fall unevenly on them.
    trait :unfair_policy do
      association :rated, factory: :policy
      dimension_key { "ascent.policy.fairness" }
      value { -60 }
    end

    # A voter whose own rent is set by the policy.
    trait :personally_affecting_policy do
      association :rated, factory: :policy
      dimension_key { "ascent.policy.affects_me" }
      value { 480 }
    end
  end
end
