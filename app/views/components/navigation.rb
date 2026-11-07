class Views::Components::Navigation < Views::ApplicationView
  def initialize
    @sections = []
  end

  def view_template(&block)
    if block
      yield(NavigationBuilder.new(self))
    else
      render_default_navigation
    end

    nav(class: "main-navigation", data: { controller: "nav-clearance nav-menu" }) do
      div(class: "nav-container") do
        div(class: "nav-topbar") do
          div(class: "nav-brand") do
            link_to root_path, class: "brand-link", aria: { label: "Ascent home" } do
              BrandMark()
              span(class: "brand-wordmark") { "Ascent" }
            end
          end

          menu_toggle

          div(class: "nav-auth") do
            Views::Components::DeviseLinks()
          end
        end

        div(class: "nav-links", id: "site-menu") do
          primary_links
          @sections.each { render_nav_section it }
        end
      end
    end
  end

  def add_section(title, &block)
    section = NavigationSection.new(title)
    yield(section) if block
    @sections << section
  end

  private

  # Voting links lead; reference pages and the public data follow in menus.
  def render_default_navigation
    add_section("Reference") do |section|
      section.link("Overview", root_path, :layout_dashboard)
      section.link("About Approval Voting", approval_voting_path, :circle_check_big)
      section.link("Glossary", glossary_path, :book_open)
      section.link("Seed data FAQ", faq_path, :git_pull_request)
      section.link("For Supporters", supporters_path, :heart_handshake)
      section.link("All Mountains", mountains_path, :mountain)
      section.link("Inquiries", new_inquiry_path, :mail)
    end
    render_data_navigation
    if current_voter&.can_review?
      add_section("Moderation") do |section|
        section.link("Channel reviews", channels_path, :circle_check_big)
      end
    end
  end

  def render_data_navigation
    add_section("Jurisdictions") do |section|
      section.link("Explore map", map_path, :map)
      section.link("Countries", countries_path, ENTITY_ICONS[:country])
      section.link("States", states_path, ENTITY_ICONS[:state])
      section.link("Counties", counties_path, ENTITY_ICONS[:county])
      section.link("Municipalities", municipalities_path, ENTITY_ICONS[:municipality])
      section.link("Districts", districts_path, ENTITY_ICONS[:district])
    end

    add_section("Governance") do |section|
      section.link("Positions", positions_path, ENTITY_ICONS[:position])
      section.link("Governance Types", governance_types_path, ENTITY_ICONS[:governance_type])
      section.link("Areas of Concern", area_of_concerns_path, ENTITY_ICONS[:area_of_concern])
      section.link("Governing Bodies", governing_bodies_path, ENTITY_ICONS[:governing_body])
      section.link("Offices", offices_path, ENTITY_ICONS[:office])
      section.link("Policies", policies_path, ENTITY_ICONS[:policy])
      section.link("Official Codes", official_codes_path, ENTITY_ICONS[:official_code])
    end

    add_section("Policy") do |section|
      section.link("Topics", topics_path, ENTITY_ICONS[:topic])
      section.link("Issues", issues_path, ENTITY_ICONS[:issue])
      section.link("Approaches", approaches_path, ENTITY_ICONS[:approach])
      section.link("Stances", stances_path, ENTITY_ICONS[:stance])
    end

    add_section("Elections") do |section|
      section.link("Years", years_path, ENTITY_ICONS[:year])
      section.link("Elections", elections_path, ENTITY_ICONS[:election])
      section.link("Races", races_path, ENTITY_ICONS[:race])
      section.link("Citizens", citizens_path, ENTITY_ICONS[:citizen])
      section.link("Candidacies", candidacies_path, ENTITY_ICONS[:candidacy])
      section.link("Organizations", organizations_path, ENTITY_ICONS[:organization])
      section.link("Parties", parties_path, ENTITY_ICONS[:party])
      section.link("Endorsements", endorsements_path, ENTITY_ICONS[:endorsement])
    end

    add_section("Voting") do |section|
      section.link("Invites leaderboard", invites_path, :users_round)
      section.link("Voters", voters_path, ENTITY_ICONS[:voter])
      section.link("Residences", residences_path, ENTITY_ICONS[:residence])
      section.link("Ratings", ratings_path, ENTITY_ICONS[:rating])
      section.link("Baselines", voter_race_baselines_path, ENTITY_ICONS[:voter_race_baseline])
    end
  end

  def primary_links
    div(class: "nav-primary") do
      link_to(ballot_path, class: nav_link_class(ballot_path, "nav-primary-link")) { link_content "My ballot", :clipboard_check }
      link_to(ballot_path(anchor: "elsewhere"), class: "nav-primary-link") { link_content "Explore races", :compass }
      link_to(new_mock_election_path, class: nav_link_class(new_mock_election_path, "nav-primary-link")) { link_content "Mock election", :flask_conical }
    end
  end

  # Phones fold the account links and sections behind this button.
  def menu_toggle
    button(type: "button", class: "nav-menu-toggle", aria: { expanded: "false", controls: "site-menu" },
      data: { action: "nav-menu#toggle", nav_menu_target: "toggle" }) do
      icon(:menu, class: "icon icon-menu nav-menu-open-icon")
      icon(:x, class: "icon icon-x nav-menu-close-icon")
      span(class: "nav-menu-label") { "Menu" }
    end
  end

  def render_nav_section(section)
    div(class: "nav-group", data: { controller: "dropdown" }) do
      div(class: "nav-group-header", data: { action: "click->dropdown#toggle" }) do
        span { section.title }
        span(class: "nav-group-arrow") { icon(:chevron_down) }
      end
      div(class: "nav-group-content", data: { dropdown_target: "menu" }) do
        section.links.each { |link| link_to(link[:path], class: nav_link_class(link[:path])) { link_content link[:text], link[:icon] } }
      end
    end
  end

  def link_content(text, icon_name)
    icon(icon_name)
    span { text }
  end

  def nav_link_class(path, base_classes = "nav-link")
    current_page?(path) ? "#{base_classes} active" : base_classes
  end

  class NavigationBuilder
    def initialize(navigation)
      @navigation = navigation
    end

    def section(title, &block)
      @navigation.add_section(title, &block)
    end
  end

  class NavigationSection
    attr_reader :title, :links

    def initialize(title)
      @title = title
      @links = []
    end

    def link(text, path, icon)
      @links << { text: text, path: path, icon: icon }
    end
  end
end
