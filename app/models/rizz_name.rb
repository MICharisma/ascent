# The name Rizz authorizes Ascent to show for one Citizen and display purpose.
# RizzNames keeps these rows in step with Rizz; rendering reads them and never
# calls Rizz.
#
# A current row with no display_name means Rizz has no name Ascent may show,
# so the page shows a neutral label. An invalidated row is waiting for a
# refetch and shows the neutral label too.
#
# display_parts splits display_name into pieces with roles, such as which is
# the family name. Null means Rizz doesn't know the name's structure.
# name_sort holds RizzName.sort_keys, for sorting in SQL.
class RizzName < ApplicationRecord
  PURPOSES = %w[referring].freeze

  belongs_to :citizen

  validates :purpose, inclusion: { in: PURPOSES }
  validates :state, inclusion: { in: %w[current invalidated] }

  def label
    display_name if state == "current"
  end

  def parts
    display_parts if label
  end

  # The keys Ascent sorts a name by (name_sort): the family name, then the
  # other names. A name whose structure Rizz doesn't know sorts by Rizz's
  # sort key, or the whole name.
  def self.sort_keys(display_name, display_parts, sort_key)
    return unless display_name
    return NameParts.sort_keys(display_parts) if display_parts
    [ sort_key.presence || display_name, "" ]
  end
end
