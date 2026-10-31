# frozen_string_literal: true

class Views::Pages::HomeView < Views::ApplicationView
  def initialize(page:, active_races:, metrics:)
    @page = page
    @active_races = active_races
    @metrics = metrics
  end

  def view_template
    div(class: "story-page home-page") do
      render_hero
      render_metrics
      render_pillars
      render_trust_section
      render_active_races
    end
  end

  private

  def render_hero
    hero = @page.fetch(:hero)
    section(class: "story-hero") do
      p(class: "story-kicker") { hero.fetch(:kicker) }
      h1(class: "story-title") { hero.fetch(:title) }
      Array(hero.fetch(:lead)).each do |paragraph|
        p(class: "story-lead") { paragraph.squish }
      end

      div(class: "story-actions") do
        link_to hero.fetch(:mountains_link), mountains_path, class: "btn-primary"
        link_to hero.fetch(:approval_voting_link), approval_voting_path, class: "btn-secondary"
        link_to hero.fetch(:supporters_link), supporters_path, class: "btn-tertiary"
      end
    end
  end

  def render_metrics
    section(class: "story-section") do
      div(class: "story-metric-grid") do
        @metrics.each do |metric_key, value|
          article(class: "story-metric-card") do
            p(class: "story-metric-value") { value.to_s }
            p(class: "story-metric-label") { @page.fetch(:metrics).fetch(metric_key) }
          end
        end
      end
    end
  end

  def render_pillars
    pillars = @page.fetch(:pillars)
    section(class: "story-section") do
      div(class: "story-section-heading") do
        p(class: "story-section-kicker") { pillars.fetch(:kicker) }
        h2(class: "story-section-title") { pillars.fetch(:title) }
      end

      div(class: "story-card-grid") do
        pillars.fetch(:items).each do |item|
          render_pillar(item.fetch(:title), item.fetch(:copy).squish)
        end
      end
    end
  end

  def render_trust_section
    trust = @page.fetch(:trust)
    section(class: "story-band") do
      div(class: "story-section-heading") do
        p(class: "story-section-kicker") { trust.fetch(:kicker) }
        h2(class: "story-section-title") { trust.fetch(:title) }
      end

      div(class: "story-card-grid story-card-grid-compact") do
        trust.fetch(:items).each do |item|
          render_trust_card(item.fetch(:title), item.fetch(:copy).squish)
        end
      end
    end
  end

  def render_active_races
    races = @page.fetch(:active_races)
    section(class: "story-section") do
      div(class: "story-section-heading") do
        p(class: "story-section-kicker") { races.fetch(:kicker) }
        h2(class: "story-section-title") { races.fetch(:title) }
      end

      if @active_races.any?
        div(class: "story-election-grid") do
          @active_races.each do |race|
            article(class: "story-election-card") do
              p(class: "story-election-context") { race_context(race) }
              h3(class: "story-election-title") { race.election.name }
              p(class: "story-election-summary") { race.description.presence || race.election.description }
              div(class: "story-card-actions") do
                link_to races.fetch(:mountain_link), mountain_path(race), class: "btn-primary"
                link_to races.fetch(:race_link), race_path(race), class: "btn-secondary"
              end
            end
          end
        end
      else
        empty = races.fetch(:empty)
        article(class: "story-callout") do
          h3(class: "story-callout-title") { empty.fetch(:title) }
          p(class: "story-callout-copy") { empty.fetch(:copy).squish }
          div(class: "story-card-actions") do
            link_to empty.fetch(:elections_link), elections_path, class: "btn-secondary"
            link_to empty.fetch(:jurisdictions_link), countries_path, class: "btn-tertiary"
          end
        end
      end
    end
  end

  def render_pillar(title, copy)
    article(class: "story-card") do
      h3(class: "story-card-title") { title }
      p(class: "story-card-copy") { copy }
    end
  end

  def render_trust_card(title, copy)
    article(class: "story-card story-card-subtle") do
      h3(class: "story-card-title") { title }
      p(class: "story-card-copy") { copy }
    end
  end
end
