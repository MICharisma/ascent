FactoryBot.define do
  factory :image do
    sequence(:url) { |n| "https://images.example.org/community-#{n}.jpg" }
    alt_text { "Neighbors at a community meeting" }
    credit { "Riverside Studio" }
    source_url { "https://example.org/photographs/community-meeting" }

    trait :uploaded do
      url { nil }
      file do
        { io: StringIO.new(File.binread(Rails.root.join("spec/fixtures/files/portrait.png"))),
          filename: "portrait.png", content_type: "image/png" }
      end
    end
  end

  factory :image_placement do
    image
    association :subject, factory: :citizen
    position { 0 }
  end
end
