# frozen_string_literal: true

# The top of a record's or a list's page: where it sits, what it is, a sentence about it, its actions,
# and, for a record a voter can bookmark, the action bar.
#   PageHeader(trail: trail_for(race), current: "Governor", eyebrow: "Connecticut · Nov 3", title: "Governor",
#     lede: "Four candidates.", record: race) { PillLink(label: "Build your mountain", path: ...) }
# A record's title shares a view-transition name with its row in a list, so it carries across.
class Views::Components::PageHeader < Views::ApplicationView
  prop :title, String
  prop :trail, Array, default: -> { [] }
  prop :current, _Nilable(String)
  prop :eyebrow, _Nilable(String)
  prop :lede, _Nilable(String)
  prop :record, _Nilable(ActiveRecord::Base)
  prop :icon_for, _Any?
  prop :modifier, _Nilable(String)
  prop :chips, _Callable?

  def view_template(&actions)
    header(class: [ "page-header", @modifier ].compact.join(" ")) do
      Breadcrumb(trail: @trail, current: @current || @title) if @trail.any?
      eyebrow if @eyebrow
      h1(class: "display-title", style: title_transition) { @title }
      div(class: "page-header-chips") { @chips.call } if @chips
      p(class: "ballot-lede") { @lede } if @lede
      div(class: "place-actions", &actions) if actions
      ActionBar(record: @record) if @record.is_a?(Engageable)
    end
  end

  private

  def eyebrow
    span(class: "eyebrow") do
      entity_icon(icon_for) if icon_for
      plain @eyebrow
    end
  end

  def icon_for
    @icon_for || @record
  end

  def title_transition
    "view-transition-name: #{dom_id(@record, :title)}" if @record
  end
end
