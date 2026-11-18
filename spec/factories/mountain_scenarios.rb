FactoryBot.define do
  factory :mountain_scenario, class: Hash do
    skip_create

    transient do
      year { Year.find_by(year: Date.current.year) || FactoryBot.create(:year, year: Date.current.year) }
      election { FactoryBot.create(:election, :mock, year: year) }
      race { FactoryBot.create(:race, :active, election: election) }
      voter do
        FactoryBot.create(:voter, first_name: Faker::Name.first_name, last_name: Faker::Name.last_name,
          email: Faker::Internet.unique.email)
      end
      candidate_count { 8 }
      baseline { 275 }
      ratings { [ 470, 425, 365, 310, 265, 205, 125, 55 ] }
    end

    initialize_with do
      candidate_names = %w[
        Avery Blair Cameron Devon Ellis Finley Gray Harper
        Jordan Kai Morgan Parker Quinn Riley Sawyer Taylor
      ]

      candidacies = Array.new(candidate_count) do |index|
        citizen = FactoryBot.create(
          :citizen,
          first_name: candidate_names.fetch(index),
          last_name: Faker::Name.last_name
        )

        FactoryBot.create(:candidacy, race: race, citizen: citizen)
      end

      voter_baseline = FactoryBot.create(
        :voter_race_baseline,
        voter: voter,
        race: race,
        baseline: baseline
      )

      created_ratings = candidacies.each_with_index.map do |candidacy, index|
        FactoryBot.create(
          :rating,
          voter: voter,
          candidacy: candidacy,
          rating: ratings.fetch(index) { (baseline + rand(-180..180)).clamp(0, 500) }
        )
      end

      {
        race: race,
        voter: voter,
        candidacies: candidacies,
        baseline: voter_baseline,
        ratings: created_ratings
      }
    end

    trait :crowded_primary do
      candidate_count { 12 }
      baseline { 285 }
      ratings { [ 485, 455, 420, 385, 350, 315, 295, 275, 235, 185, 120, 45 ] }
    end

    trait :knife_edge do
      candidate_count { 8 }
      baseline { 300 }
      ratings { [ 465, 405, 335, 307, 294, 275, 160, 70 ] }
    end

    trait :enthusiastic do
      candidate_count { 8 }
      baseline { 225 }
      ratings { [ 490, 450, 410, 365, 320, 270, 215, 125 ] }
    end

    trait :selective do
      candidate_count { 8 }
      baseline { 365 }
      ratings { [ 480, 420, 355, 315, 265, 210, 145, 75 ] }
    end

    trait :polarized do
      candidate_count { 8 }
      baseline { 250 }
      ratings { [ 495, 465, 430, 380, 115, 80, 35, 5 ] }
    end

    factory :crowded_primary_mountain, traits: [ :crowded_primary ]
    factory :knife_edge_mountain, traits: [ :knife_edge ]
    factory :enthusiastic_mountain, traits: [ :enthusiastic ]
    factory :selective_mountain, traits: [ :selective ]
    factory :polarized_mountain, traits: [ :polarized ]
  end
end
