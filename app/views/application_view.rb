# frozen_string_literal: true

class Views::ApplicationView < Phlex::HTML
  # Declare arguments with `prop :name, Type` instead of writing an initializer.
  extend Literal::Properties

  # Common helpers are included here to be available in all views.
  include ScaffoldUiHelper
  include Phlex::Rails::Helpers::DOMID
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::ButtonTo
  include Phlex::Rails::Helpers::Flash
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::SimpleFormat
  include Phlex::Rails::Helpers::Pluralize
  include Phlex::Rails::Helpers::CurrentPage
  include Phlex::Rails::Helpers::Request
  include Phlex::Rails::Helpers::TurboFrameTag

  include Devise::Controllers::Helpers
  include ActionPolicy::Behaviour

  include Views::Components
  include Views::Partials

  def self.inherited(subclass)
    super
    auto_include_namespace_module subclass
  end

  private

  def default_authorization_policy_class
    ApplicationRecordPolicy
  end

  # Simulated mountain data invents candidates and ratings, so only admins see the controls for it.
  def can_simulate_mountains?
    allowed_to?(:simulate?, :mountain, context: { voter: current_voter })
  end

  # A Lucide icon by name, e.g. icon(:share_2). Hidden from screen readers; the text beside it carries the meaning.
  def icon(name, **attributes)
    render PhlexIcons::Lucide.const_get(name.to_s.camelize).new(class: "icon icon-#{name.to_s.dasherize}", aria: { hidden: true }, **attributes)
  end

  # The Lucide icon that stands for each kind of record, wherever records are listed or titled.
  ENTITY_ICONS = {
    race: :vote, election: :calendar, candidacy: :badge_check, citizen: :user_round,
    office: :landmark, position: :briefcase, country: :globe, state: :map, county: :map_pinned,
    municipality: :building_2, district: :layout_grid, topic: :tag, issue: :circle_question_mark,
    approach: :route, stance: :quote, governing_body: :columns_3, policy: :scroll_text, official_code: :file_text,
    year: :calendar_range, governance_type: :network, area_of_concern: :target, voter: :user, residence: :house, rating: :gauge,
    voter_race_baseline: :ruler_dimension_line, organization: :building_2, party: :flag, endorsement: :badge_check
  }.freeze

  def entity_icon(record_or_model)
    icon(ENTITY_ICONS.fetch(record_or_model.model_name.element.to_sym, :circle))
  end

  # The links back up from a record to its section of the site, for a Breadcrumb's trail.
  def trail_for(record)
    case record
    when Race then [ [ "Elections", elections_path ], [ record.election.name, record.election ] ]
    when Candidacy then trail_for(record.race) + [ [ record.race.office.position.title, record.race ] ]
    when Office then [ [ "Offices", offices_path ], [ record.jurisdiction.name, record.jurisdiction.jurisdictionable ] ]
    when JurisdictionOwner then place_trail(record)
    else chain_trail(record)
    end
  end

  # The places a place sits within, from its country down, by the jurisdiction tree.
  def place_trail(place)
    above = []
    jurisdiction = place.jurisdiction&.parent
    while jurisdiction
      above.unshift(jurisdiction)
      jurisdiction = jurisdiction.parent
    end
    above.map { [ it.name, it.jurisdictionable ] }
  end

  # A record's parents in its own hierarchy, such as an approach's issue and topic, or else its section.
  def chain_trail(record)
    parents = record.build_hierarchy_chain[0...-1]
    return parents.map { [ it.name, it ] } if parents.any?

    [ [ record.model_name.human.pluralize, polymorphic_path(record.class) ] ]
  end

  # A race still to be decided: open for mountains, and its election day not yet past.
  def ahead?(race)
    race.election.open_to_rating? && race.election.election_date >= Date.current
  end

  # A section's heading, with a short note beside it such as a count.
  def section_heading(title, subtitle = nil)
    div(class: "place-section-heading") do
      h2(class: "card-title") { title }
      span(class: "place-section-subtitle") { subtitle } if subtitle
    end
  end

  def delimited(number)
    ActiveSupport::NumberHelper.number_to_delimited(number)
  end

  # A share from 0 to 100 as a whole percent, or a dash when there is none.
  def percent(share)
    share ? "#{share.round}%" : "—"
  end

  # How far a date is from today: "in 8 days", "today", "3 days ago".
  def relative_days(date)
    days = (date - Date.current).to_i
    if days.positive? then "in #{pluralize(days, "day")}"
    elsif days.zero? then "today"
    else "#{pluralize(-days, "day")} ago"
    end
  end

  # The popover a ballot opens on a candidate's name, and the Turbo frame its card loads into.
  def candidate_popover_id(candidacy)
    "candidate-popover-#{candidacy.id}"
  end

  def jurisdiction_link(jurisdiction)
    link_to jurisdiction.name, jurisdiction.jurisdictionable, class: "link jurisdiction"
  end

  # All views that inherit from this have access to methods on their namespace module, including Kits
  def self.auto_include_namespace_module(klass)
    # Extract the module name from the class name
    # Views::Candidacies::EditView -> Views::Candidacies
    class_name = klass.name; return unless class_name&.start_with?("Views::")
    parts = class_name.split("::"); return unless parts.length >= 3  # Views, Namespace, ClassName
    module_name = parts[0..2].join("::")  # Views::Issues, Views::Candidacies, etc.

    begin
      target_module = module_name.constantize
      # Only include if it's a Module (not a Class) and is different from the class itself
      if target_module.is_a?(Module) && !target_module.is_a?(Class) && target_module != klass
        klass.include target_module
      end
    rescue NameError
      # This allows views that don't have a corresponding module
    end
  end
end
