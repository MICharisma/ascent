class StanceSeeder
  def self.seed
    # Create comprehensive stances showing candidate positions on key issues
    stance_configurations = [
      # Education Stances
      {
        candidacy_title: "Mayor",
        issue_title: "School Funding Shortfalls",
        approach_title: "Education Revenue Bond Initiative",
        priority_level: "high",
        explanation: "Education funding is my top priority as Mayor. I will champion a dedicated education bond measure that provides stable, long-term funding for our schools while maintaining transparency and accountability in spending. Our children deserve modern facilities, smaller class sizes, and the resources they need to compete in the global economy.",
        evidence_links: "Voting record on education issues, Endorsements from Teachers Union and PTA, Budget analysis showing funding gaps"
      },
      {
        candidacy_title: "State Representative",
        issue_title: "Student Achievement Gaps",
        approach_title: "Comprehensive Early Childhood Initiative",
        priority_level: "high",
        explanation: "Achievement gaps start early and compound over time. As your State Representative, I will advocate for universal pre-K funding, expand Head Start programs, and ensure seamless transitions from early childhood to elementary education. Every child deserves an equal opportunity to succeed regardless of their zip code.",
        evidence_links: "Co-sponsored early childhood legislation, Research on achievement gap interventions, Support from child advocacy organizations"
      },

      # Healthcare Stances
      {
        candidacy_title: "County Commissioner",
        issue_title: "Rural Healthcare Access",
        approach_title: "Mobile Health Clinic Network",
        priority_level: "high",
        explanation: "Rural residents shouldn't have to choose between their health and traveling hours for basic care. I will establish a county-wide mobile health network with nurse practitioners, telemedicine capabilities, and partnerships with urban medical centers to bring quality healthcare directly to underserved communities.",
        evidence_links: "County health needs assessment, Mobile clinic pilot program results, Partnerships with regional hospitals"
      },
      {
        candidacy_title: "Governor",
        issue_title: "Mental Health Service Gaps",
        approach_title: "Integrated Community Mental Health System",
        priority_level: "high",
        explanation: "Mental health is health, period. As Governor, I will expand community mental health centers, integrate services with primary care, and ensure no one waits weeks for crisis intervention. We must treat mental health with the same urgency and resources we provide for physical health emergencies.",
        evidence_links: "Mental health legislation sponsored, Crisis intervention program funding, Endorsements from mental health professionals"
      },

      # Housing Stances
      {
        candidacy_title: "Council Member",
        issue_title: "Affordable Housing Shortage",
        approach_title: "Inclusionary Housing Ordinance",
        priority_level: "high",
        explanation: "Working families are being priced out of our community. I support requiring new developments to include affordable units while providing developers with density bonuses and streamlined permitting. We must preserve economic diversity in our neighborhoods and ensure teachers, firefighters, and service workers can afford to live where they serve.",
        evidence_links: "Housing affordability analysis, Developer stakeholder meetings, Support from labor unions and housing advocates"
      },
      {
        candidacy_title: "Mayor",
        issue_title: "Homelessness Crisis",
        approach_title: "Housing First Initiative",
        priority_level: "high",
        explanation: "Housing first works. As Mayor, I will implement evidence-based programs that provide immediate permanent housing combined with wraparound services. It's more cost-effective than emergency shelter cycling and more humane than allowing people to remain on the streets.",
        evidence_links: "Housing First program evaluation data, Partnerships with service providers, Budget analysis showing cost savings"
      },

      # Transportation Stances
      {
        candidacy_title: "Council Member",
        issue_title: "Traffic Congestion",
        approach_title: "Intelligent Transportation Management System",
        priority_level: "medium",
        explanation: "Smart technology can reduce congestion without expensive infrastructure. I support adaptive traffic signals, real-time monitoring, and coordinated timing that optimizes traffic flow during peak hours. This improves air quality, reduces commute times, and enhances quality of life for all residents.",
        evidence_links: "Traffic flow analysis, Smart city technology research, Environmental impact assessment"
      },
      {
        candidacy_title: "County Commissioner",
        issue_title: "Public Transit Inadequacy",
        approach_title: "Bus Rapid Transit System",
        priority_level: "high",
        explanation: "Reliable public transit is essential for economic mobility and environmental sustainability. Bus rapid transit provides rail-like service at a fraction of the cost, with dedicated lanes, frequent service, and real-time information that makes transit a viable alternative to driving.",
        evidence_links: "Regional transit needs assessment, BRT system case studies, Federal transit funding applications"
      },

      # Environmental Stances
      {
        candidacy_title: "State Senator",
        issue_title: "Climate Change Impacts",
        approach_title: "Climate Resilience and Adaptation Plan",
        priority_level: "high",
        explanation: "Climate change is happening now, and we must prepare our communities for increased extreme weather, flooding, and heat. As State Senator, I will secure funding for resilient infrastructure, green spaces, and emergency preparedness that protects lives and property while creating good-paying jobs.",
        evidence_links: "Climate legislation voting record, Environmental endorsements, Renewable energy project development"
      },
      {
        candidacy_title: "Mayor",
        issue_title: "Air and Water Pollution",
        approach_title: "Comprehensive Environmental Monitoring and Enforcement",
        priority_level: "high",
        explanation: "Clean air and water are fundamental rights. I will strengthen environmental monitoring, increase enforcement of pollution regulations, and require real-time pollution reporting. Industrial companies must be held accountable for protecting the health of our families and environment.",
        evidence_links: "Environmental protection advocacy, Pollution violation enforcement data, Public health impact studies"
      },

      # Public Safety Stances
      {
        candidacy_title: "Sheriff",
        issue_title: "Rising Crime Rates",
        approach_title: "Community Policing and Neighborhood Engagement",
        priority_level: "high",
        explanation: "Effective policing requires community trust and partnership. As Sheriff, I will expand community policing with officers assigned to specific neighborhoods, regular community meetings, and civilian oversight that ensures accountability while building relationships that prevent crime before it happens.",
        evidence_links: "Community policing training and experience, Crime reduction program results, Support from neighborhood associations"
      },
      {
        candidacy_title: "District Attorney",
        issue_title: "Substance Abuse and Addiction",
        approach_title: "Comprehensive Addiction Treatment System",
        priority_level: "high",
        explanation: "We cannot arrest our way out of the addiction crisis. As District Attorney, I will expand drug courts, diversion programs, and treatment options that address the root causes of addiction-related crime. Treatment is more effective and cost-efficient than incarceration for non-violent offenses.",
        evidence_links: "Drug court program outcomes, Treatment vs. incarceration cost analysis, Support from addiction treatment professionals"
      },

      # Economic Development Stances
      {
        candidacy_title: "Mayor",
        issue_title: "High Unemployment",
        approach_title: "Workforce Development and Skills Training",
        priority_level: "high",
        explanation: "Good jobs strengthen families and communities. I will partner with employers and educational institutions to provide job training in high-demand fields, create apprenticeship programs, and ensure residents have pathways to career advancement without leaving our community.",
        evidence_links: "Workforce development partnerships, Job placement program success rates, Employer skill needs assessment"
      },
      {
        candidacy_title: "Council Member",
        issue_title: "Small Business Struggles",
        approach_title: "Small Business Support and Development Program",
        priority_level: "medium",
        explanation: "Small businesses are the backbone of our local economy. I support streamlined permitting, technical assistance, microloans, and buy-local campaigns that help entrepreneurs start and grow businesses that create jobs and keep dollars circulating in our community.",
        evidence_links: "Small business owner testimonials, Economic impact of local businesses, Regulatory streamlining proposals"
      },

      # Social Services Stances
      {
        candidacy_title: "County Commissioner",
        issue_title: "Senior Care Service Gaps",
        approach_title: "Comprehensive Senior Services Center",
        priority_level: "high",
        explanation: "Our seniors built this community and deserve dignity and support as they age. I will establish comprehensive senior centers offering healthcare, transportation, meals, and social activities that help seniors remain independent and connected to their community.",
        evidence_links: "Senior needs assessment survey, Aging in place program research, Support from senior advocacy groups"
      },
      {
        candidacy_title: "School Board",
        issue_title: "Food Insecurity",
        approach_title: "School and Summer Meal Program Expansion",
        priority_level: "high",
        explanation: "No child should go hungry in our community. As a School Board member, I will expand free meal programs, implement universal school breakfast, and ensure children have access to nutritious food year-round through summer and weekend programs.",
        evidence_links: "Childhood hunger statistics, Nutrition program impact studies, Support from child nutrition advocates"
      },

      # Infrastructure and Technology Stances
      {
        candidacy_title: "Mayor",
        issue_title: "Digital Divide",
        approach_title: "Municipal Broadband Infrastructure",
        priority_level: "medium",
        explanation: "High-speed internet is essential infrastructure like roads and water. I support municipal broadband or public-private partnerships that ensure affordable, reliable internet access for all residents, closing the digital divide that limits educational and economic opportunities.",
        evidence_links: "Digital equity assessment, Municipal broadband feasibility study, Support from digital inclusion advocates"
      },
      {
        candidacy_title: "Public Works Director",
        issue_title: "Aging Water and Sewer Systems",
        approach_title: "Water Infrastructure Modernization Program",
        priority_level: "high",
        explanation: "Clean, reliable water and sewer systems are fundamental to public health and economic development. I will implement systematic infrastructure replacement, smart water management, and sustainable funding that prevents service disruptions and protects our environment.",
        evidence_links: "Infrastructure condition assessment, Water system modernization expertise, Professional engineering credentials"
      },

      # Cultural and Recreation Stances
      {
        candidacy_title: "Council Member",
        issue_title: "Cultural Funding Shortfalls",
        approach_title: "Public-Private Arts Partnership",
        priority_level: "medium",
        explanation: "Arts and culture strengthen community identity and drive economic development. I support partnerships with businesses and foundations that supplement public funding, ensuring vibrant cultural programming that attracts visitors, supports artists, and enriches the lives of residents.",
        evidence_links: "Cultural economic impact studies, Arts organization partnerships, Tourism development through cultural programming"
      },
      {
        candidacy_title: "Parks and Recreation Director",
        issue_title: "Recreation Facility Inadequacy",
        approach_title: "Community Recreation Center Development",
        priority_level: "high",
        explanation: "Quality recreation facilities promote health, reduce youth crime, and build community connections. I will develop modern recreation centers with fitness facilities, sports courts, and programming for all ages, prioritizing underserved neighborhoods and accessibility for residents with disabilities.",
        evidence_links: "Recreation needs assessment, Youth development program outcomes, Accessible facility design expertise"
      }
    ]

    skipped_positions = []

    stance_configurations.each do |config|
      # Simulated stances only attach to candidacies in mock elections, never to real candidates.
      candidacy = Candidacy.joins(race: [ :election, { office: :position } ])
                          .merge(Election.mock)
                          .where(positions: { title: config[:candidacy_title] })
                          .first

      unless candidacy
        skipped_positions << config[:candidacy_title]
        next
      end

      # Find the issue by title
      issue = Issue.find_by(title: config[:issue_title])
      unless issue
        puts "\n❌ Issue not found: #{config[:issue_title]}"
        next
      end

      # Find the approach by title
      approach = Approach.find_by(title: config[:approach_title])
      unless approach
        puts "\n❌ Approach not found: #{config[:approach_title]}"
        next
      end

      # Create the stance
      stance = Stance.find_or_create_by(
        candidacy: candidacy,
        approach: approach
      ) do |s|
        s.explanation = config[:explanation]
        s.priority_level = config[:priority_level]
        s.evidence_links = config[:evidence_links]
      end

      if stance.persisted?
        print "."
      else
        puts "\n❌ Failed to create stance for #{candidacy.citizen.first_name} #{candidacy.citizen.last_name} on #{issue.title}"
        puts "   Errors: #{stance.errors.full_messages.join(', ')}"
      end
    end

    puts " #{Stance.count} stances"
    puts "Skipped stances for positions without a mock candidacy: #{skipped_positions.uniq.join(', ')}" if skipped_positions.any?
  end
end
