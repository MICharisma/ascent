# frozen_string_literal: true

class Views::Ratings::IndexView < Views::ApplicationView
  prop :ratings, ActiveRecord::Relation
  prop :pagy, _Nilable(Pagy)

  def view_template
    ResourceIndex(collection: @ratings, pagy: @pagy, lede: "Every rating voters have given. Only admins see this list.") do |rating|
      ListRow(record: rating, title: rating.voter.full_name, meta: "#{rating.candidacy.citizen.display_name} · #{rating.candidacy.race.office.name} · rated #{rating.rating}")
    end
  end
end
