FactoryBot.define do
  factory :stance do
    association :candidacy
    association :approach
    explanation { "I believe this approach will effectively address this critical issue through comprehensive policy implementation, community engagement, and sustainable funding mechanisms that ensure long-term success and measurable outcomes." }
    priority_level { "high" }
    evidence_links { "https://example.com/policy-research, https://example.com/case-studies, https://example.com/voting-record" }
    trait :high_priority do
      priority_level { "high" }
      explanation { "This is one of my top policy priorities. I am committed to immediate action and have developed a comprehensive plan with specific timelines, funding sources, and accountability measures to ensure successful implementation." }
      evidence_links { "https://example.com/detailed-plan, https://example.com/budget-analysis, https://example.com/stakeholder-support" }
    end
    trait :medium_priority do
      priority_level { "medium" }
      explanation { "This important issue requires thoughtful attention and collaborative solutions. I support this approach as part of a balanced policy agenda that addresses multiple community needs while ensuring fiscal responsibility." }
      evidence_links { "https://example.com/research-study, https://example.com/community-input" }
    end
    trait :low_priority do
      priority_level { "low" }
      explanation { "While this issue has merit, other priorities take precedence given current resource constraints. I support exploring this approach through pilot programs and community partnerships before full implementation." }
      evidence_links { "https://example.com/background-research" }
    end
    trait :education_stance do
      association :approach, factory: :school_improvement_approach
      priority_level { "high" }
      explanation { "Education is the foundation of our community's future. I strongly support increased school funding through dedicated revenue sources, teacher recruitment and retention programs, and modernized facilities that prepare our students for 21st century careers." }
      evidence_links { "https://example.com/education-plan, https://example.com/teacher-endorsements, https://example.com/student-outcomes-data" }
    end
    trait :healthcare_stance do
      association :approach, factory: :mobile_health_approach
      priority_level { "high" }
      explanation { "Healthcare is a fundamental right. Mobile health clinics and expanded telehealth services will ensure all residents have access to quality care regardless of location or economic status, reducing emergency room visits and improving preventive care." }
      evidence_links { "https://example.com/healthcare-proposal, https://example.com/rural-health-data, https://example.com/physician-support" }
    end
    trait :housing_stance do
      association :approach, factory: :affordable_housing_approach
      priority_level { "high" }
      explanation { "Every working family deserves access to safe, affordable housing. I support inclusionary zoning, housing trust funds, and public-private partnerships to create mixed-income communities that preserve neighborhood character while addressing housing needs." }
      evidence_links { "https://example.com/housing-strategy, https://example.com/affordability-analysis, https://example.com/developer-partnerships" }
    end
    trait :transportation_stance do
      association :approach, factory: :transit_expansion_approach
      priority_level { "medium" }
      explanation { "Improved public transit reduces traffic congestion, air pollution, and transportation costs for families. I support bus rapid transit and expanded service that connects residential areas with employment centers and essential services." }
      evidence_links { "https://example.com/transit-plan, https://example.com/ridership-projections, https://example.com/environmental-impact" }
    end
    trait :environmental_stance do
      association :approach, factory: :environmental_regulations_approach
      priority_level { "high" }
      explanation { "Environmental protection is essential for public health and economic sustainability. Stronger regulations, monitoring, and enforcement will protect our air and water quality while supporting businesses in adopting clean technologies." }
      evidence_links { "https://example.com/environmental-record, https://example.com/pollution-data, https://example.com/green-business-support" }
    end
    trait :economic_stance do
      association :approach, factory: :job_training_approach
      priority_level { "high" }
      explanation { "Economic opportunity for all residents strengthens our entire community. Job training programs, apprenticeships, and small business support create pathways to good-paying careers while meeting employer needs for skilled workers." }
      evidence_links { "https://example.com/workforce-development, https://example.com/employer-partnerships, https://example.com/economic-impact" }
    end
    trait :progressive_stance do
      priority_level { "high" }
      explanation { "Bold action is needed to address systemic challenges and create equitable opportunities for all residents. I support comprehensive solutions that prioritize community needs over special interests and ensure sustainable, inclusive growth." }
      evidence_links { "https://example.com/progressive-platform, https://example.com/grassroots-endorsements, https://example.com/policy-research" }
    end
    trait :moderate_stance do
      priority_level { "medium" }
      explanation { "Effective governance requires balanced approaches that bring citizens together around practical solutions. I support evidence-based policies that address community needs while maintaining fiscal responsibility and broad public support." }
      evidence_links { "https://example.com/bipartisan-support, https://example.com/cost-benefit-analysis, https://example.com/implementation-timeline" }
    end
    trait :conservative_stance do
      priority_level { "medium" }
      explanation { "Responsible governance prioritizes proven approaches, fiscal discipline, and community values. I support solutions that strengthen families, support local businesses, and preserve what makes our community special while addressing legitimate needs." }
      evidence_links { "https://example.com/conservative-principles, https://example.com/fiscal-analysis, https://example.com/community-values" }
    end
    factory :high_priority_stance, traits: [ :high_priority ]
    factory :medium_priority_stance, traits: [ :medium_priority ]
    factory :low_priority_stance, traits: [ :low_priority ]
    factory :education_policy_stance, traits: [ :education_stance ]
    factory :healthcare_policy_stance, traits: [ :healthcare_stance ]
    factory :housing_policy_stance, traits: [ :housing_stance ]
    factory :transportation_policy_stance, traits: [ :transportation_stance ]
    factory :environmental_policy_stance, traits: [ :environmental_stance ]
    factory :economic_policy_stance, traits: [ :economic_stance ]
    factory :progressive_candidate_stance, traits: [ :progressive_stance ]
    factory :moderate_candidate_stance, traits: [ :moderate_stance ]
    factory :conservative_candidate_stance, traits: [ :conservative_stance ]
  end
end
