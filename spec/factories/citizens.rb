FactoryBot.define do
  factory :citizen do
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    middle_name { Faker::Name.middle_name }
    email { Faker::Internet.unique.email }
    birth_date { Faker::Date.birthday(min_age: 25, max_age: 80) }
    bio {
      [
        "Dedicated public servant committed to representing the community's interests",
        "Experienced leader focused on bringing positive change to our community",
        "Passionate advocate for transparent and effective governance",
        "Community-minded individual with a strong track record of public service",
        "Committed to working across party lines to solve important local issues"
      ].sample
    }

    trait :young_candidate do
      first_name { Faker::Name.first_name }
      last_name { Faker::Name.last_name }
      middle_name { Faker::Name.middle_name }
      birth_date { Faker::Date.birthday(min_age: 25, max_age: 35) }
      bio {
        [
          "Young professional bringing fresh perspectives and innovative solutions to local government",
          "Recent graduate with new ideas and energy for tackling community challenges",
          "Tech-savvy millennial focused on modernizing government operations",
          "Emerging leader committed to representing the next generation's interests"
        ].sample
      }
    end

    trait :experienced_politician do
      first_name { Faker::Name.first_name }
      last_name { Faker::Name.last_name }
      middle_name { Faker::Name.middle_name }
      birth_date { Faker::Date.birthday(min_age: 50, max_age: 75) }
      bio {
        [
          "Veteran politician with #{rand(15..35)}+ years of experience in public service and legislative leadership",
          "Seasoned statesperson with deep knowledge of government operations and policy development",
          "Former #{[ 'mayor', 'city council member', 'state legislator', 'county commissioner' ].sample} with proven leadership experience"
        ].sample
      }
    end

    trait :business_leader do
      first_name { Faker::Name.first_name }
      last_name { Faker::Name.last_name }
      middle_name { Faker::Name.middle_name }
      birth_date { Faker::Date.birthday(min_age: 40, max_age: 65) }
      bio {
        industry = [ 'technology', 'healthcare', 'manufacturing', 'retail', 'consulting' ].sample
        [
          "Successful #{industry} leader transitioning to public service to bring private sector efficiency to government",
          "Entrepreneur and business owner committed to economic development and job creation",
          "Corporate executive with experience managing large budgets and complex operations"
        ].sample
      }
    end

    trait :community_activist do
      first_name { Faker::Name.first_name }
      last_name { Faker::Name.last_name }
      middle_name { Faker::Name.middle_name }
      birth_date { Faker::Date.birthday(min_age: 30, max_age: 60) }
      bio {
        cause = [ 'social justice', 'environmental protection', 'affordable housing', 'healthcare access', 'education equity' ].sample
        [
          "Grassroots organizer and community activist with deep roots in local #{cause} movements",
          "Long-time advocate for #{cause} seeking to bring community voices to government",
          "Nonprofit leader with experience mobilizing residents around important issues"
        ].sample
      }
    end

    trait :educator do
      first_name { Faker::Name.first_name }
      last_name { Faker::Name.last_name }
      middle_name { Faker::Name.middle_name }
      birth_date { Faker::Date.birthday(min_age: 35, max_age: 65) }
      bio {
        role = [ 'school principal', 'teacher', 'superintendent', 'school board member' ].sample
        [
          "Former #{role} and education advocate focused on improving public education funding and quality",
          "Lifelong educator committed to ensuring every child has access to excellent schools",
          "Education professional with #{rand(10..25)} years of experience in the classroom and administration"
        ].sample
      }
    end

    trait :veteran do
      first_name { Faker::Name.first_name }
      last_name { Faker::Name.last_name }
      middle_name { Faker::Name.middle_name }
      birth_date { Faker::Date.birthday(min_age: 35, max_age: 65) }
      bio {
        branch = [ 'Army', 'Navy', 'Air Force', 'Marines', 'Coast Guard' ].sample
        rank = [ 'Sergeant', 'Lieutenant', 'Captain', 'Major', 'Colonel' ].sample
        [
          "#{branch} veteran with leadership experience seeking to serve the community through public office",
          "Former #{rank} committed to bringing military values of service and integrity to civilian leadership",
          "Combat veteran focused on supporting fellow veterans and strengthening national security"
        ].sample
      }
    end

    trait :no_middle_name do
      middle_name { nil }
    end

    trait :long_bio do
      bio {
        Faker::Lorem.paragraph(sentence_count: rand(8..15), supplemental: false, random_sentences_to_add: rand(3..7))
      }
    end

    trait :minimal_bio do
      bio { "Candidate for public office." }
    end

    # Named factories for common scenarios
    factory :young_candidate, traits: [ :young_candidate ]
    factory :experienced_politician, traits: [ :experienced_politician ]
    factory :business_leader, traits: [ :business_leader ]
    factory :community_activist, traits: [ :community_activist ]
    factory :educator_candidate, traits: [ :educator ]
    factory :veteran_candidate, traits: [ :veteran ]
    factory :citizen_no_middle_name, traits: [ :no_middle_name ]
  end
end
