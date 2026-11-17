# A record voters can rate on curated qualities, each on the shared standard scale.
# These ratings stand apart from the mountain: they never change a ballot or a baseline.
module DimensionRated
  extend ActiveSupport::Concern

  included do
    has_many :dimension_ratings, as: :rated, dependent: :destroy
  end

  class_methods do
    def rating_dimension(name, question:, low_label:, high_label:)
      rating_dimensions << SharedRatings::Scales.standard(key: "ascent.#{model_name.singular}.#{name}", version: 1,
        question: question, low_label: low_label, high_label: high_label)
    end

    def rating_dimensions
      @rating_dimensions ||= []
    end

    def rating_dimension_for(key)
      rating_dimensions.find { it.key == key }
    end
  end

  def voters_average_on(dimension)
    dimension_ratings.where(dimension_key: dimension.key).pick Arel.sql("COUNT(*)"), Arel.sql("AVG(value)")
  end
end
