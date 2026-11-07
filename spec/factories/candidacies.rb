FactoryBot.define do
  factory :candidacy do
    association :citizen
    association :race
    status { "active" }
    announcement_date { Faker::Date.between(from: 1.year.ago, to: 1.month.ago) }
    transient do
      # The printed label of the candidacy's one ballot line; nil leaves it without lines.
      party_label {
        [
          "Independent",
          "Democratic Party",
          "Republican Party",
          "Green Party",
          "Libertarian Party",
          "Working Families Party",
          "Progressive Party"
        ].sample
      }
    end

    after(:build) do |candidacy, evaluator|
      candidacy.ballot_lines.build(label: evaluator.party_label, kind: "party", position: 1) if evaluator.party_label
    end

    platform_summary {
      focus_areas = [
        "economic development and job creation",
        "education funding and school quality",
        "healthcare access and affordability",
        "environmental protection and sustainability",
        "public safety and community policing",
        "transportation and infrastructure",
        "affordable housing and homelessness",
        "social justice and equality",
        "government transparency and accountability",
        "small business support and entrepreneurship"
      ]

      selected_areas = focus_areas.sample(rand(2..4))
      "Committed to #{selected_areas.join(', ')}, with a focus on practical solutions that bring our community together."
    }

    trait :active do
      status { "active" }
      announcement_date { Faker::Date.between(from: 6.months.ago, to: 1.month.ago) }
    end

    trait :withdrawn do
      status { "withdrawn" }
      announcement_date { Faker::Date.between(from: 1.year.ago, to: 2.months.ago) }
      platform_summary {
        [
          "Campaign withdrawn due to personal reasons",
          "Withdrew from race to focus on family commitments",
          "Suspended campaign due to health concerns",
          "Withdrew to support another candidate with similar values"
        ].sample
      }
    end

    trait :suspended do
      status { "suspended" }
      announcement_date { Faker::Date.between(from: 8.months.ago, to: 2.months.ago) }
      platform_summary {
        [
          "Campaign temporarily suspended pending investigation",
          "Campaign on hold while addressing campaign finance questions",
          "Temporary suspension to address personal matters"
        ].sample
      }
    end

    trait :democrat do
      party_label { "Democratic Party" }
      platform_summary {
        priorities = [
          "expanding healthcare access",
          "investing in public education",
          "addressing climate change",
          "promoting social justice",
          "strengthening worker rights",
          "expanding affordable housing",
          "improving mental health services"
        ]

        selected = priorities.sample(rand(2..3))
        "Progressive policies focused on #{selected.join(', ')}, working to build an economy that works for everyone."
      }
    end

    trait :republican do
      party_label { "Republican Party" }
      platform_summary {
        priorities = [
          "fiscal responsibility",
          "strong national defense",
          "supporting small businesses",
          "protecting constitutional rights",
          "reducing government regulation",
          "law and order",
          "traditional family values"
        ]

        selected = priorities.sample(rand(2..3))
        "Conservative values emphasizing #{selected.join(', ')}, committed to limited government and individual liberty."
      }
    end

    trait :independent do
      party_label { "Independent" }
      platform_summary {
        "Non-partisan approach focusing on practical solutions and community needs, working across party lines to get things done."
      }
    end

    trait :green do
      party_label { "Green Party" }
      platform_summary {
        priorities = [
          "environmental sustainability",
          "renewable energy transition",
          "social justice",
          "grassroots democracy",
          "economic equality",
          "peace and non-violence"
        ]

        selected = priorities.sample(rand(2..3))
        "Green values centered on #{selected.join(', ')}, building a sustainable future for all."
      }
    end

    trait :early_announcement do
      announcement_date { Faker::Date.between(from: 15.months.ago, to: 12.months.ago) }
    end

    trait :late_announcement do
      announcement_date { Faker::Date.between(from: 2.months.ago, to: 2.weeks.ago) }
    end

    # Named factories for common scenarios
    factory :active_candidacy, traits: [ :active ]
    factory :withdrawn_candidacy, traits: [ :withdrawn ]
    factory :democrat_candidacy, traits: [ :active, :democrat ]
    factory :republican_candidacy, traits: [ :active, :republican ]
    factory :independent_candidacy, traits: [ :active, :independent ]
    factory :green_candidacy, traits: [ :active, :green ]
    factory :early_candidacy, traits: [ :active, :early_announcement ]
    factory :late_candidacy, traits: [ :active, :late_announcement ]
  end
end
