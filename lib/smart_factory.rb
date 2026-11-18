# frozen_string_literal: true

# SmartFactory provides intelligent factory creation with conditional reuse
# to reduce data duplication in development while maintaining realistic diversity.
#
# Example usage:
#   SmartFactory.create_or_reuse(:citizen, count: 5, reuse_likelihood: 7)
#   SmartFactory.create_or_reuse(:candidacy, :democrat, count: 3, reuse_likelihood: 4, race: race)
#
module SmartFactory
  class << self
    # Creates or reuses factory objects based on reuse likelihood
    #
    # @param factory_name [Symbol] The factory name (e.g., :citizen, :candidacy)
    # @param traits [Array<Symbol>] Factory traits to apply
    # @param count [Integer] Number of objects needed (default: 1)
    # @param reuse_likelihood [Integer] Likelihood of reusing existing objects (1-10, default: 5)
    # @param **attributes [Hash] Additional attributes to pass to the factory
    # @return [Array<ActiveRecord::Base>] Array of created/reused objects
    #
    def create_or_reuse(*traits, factory_name: nil, count: 1, reuse_likelihood: 5, **attributes)
      # Handle both positional and keyword arguments for factory_name
      if factory_name.nil? && traits.first.is_a?(Symbol)
        factory_name = traits.shift
      elsif factory_name.nil?
        raise ArgumentError, "Factory name must be provided"
      end

      # Validate inputs
      raise ArgumentError, "Count must be positive" unless count.positive?
      raise ArgumentError, "Reuse likelihood must be between 1-10" unless reuse_likelihood.between?(1, 10)

      results = []

      count.times do
        if should_reuse?(reuse_likelihood) && (existing = find_reusable_object(factory_name, traits, attributes))
          results << existing
        else
          results << create_new_object(factory_name, traits, attributes)
        end
      end

      count == 1 ? results.first : results
    end

    # Creates or reuses objects specifically for mountain simulation
    # Uses predefined reuse patterns optimized for realistic election data
    #
    def create_for_mountain_simulation(factory_name, traits = [], count: 1, **attributes)
      # Reuse patterns optimized for mountain simulation
      reuse_patterns = {
        citizen: 3,           # Low reuse - want diverse candidates
        candidacy: 2,        # Very low reuse - each candidacy should be unique
        rating: 1,           # No reuse - each rating is voter-specific
        stance: 1,           # No reuse - each stance is candidacy-specific
        voter_race_baseline: 8      # High reuse - voters often have similar standards
      }

      reuse_likelihood = reuse_patterns[factory_name] || 5
      create_or_reuse(*traits, factory_name: factory_name, count: count, reuse_likelihood: reuse_likelihood, **attributes)
    end

    private

    # Determines if we should attempt to reuse an existing object
    def should_reuse?(reuse_likelihood)
      rand(1..10) <= reuse_likelihood
    end

    # Finds a suitable existing object for reuse
    def find_reusable_object(factory_name, traits, attributes)
      model_class = factory_name.to_s.classify.constantize

      # Build a query to find compatible existing objects
      query = model_class.all

      # Apply attribute filters (only for simple attributes)
      attributes.each do |key, value|
        next if value.is_a?(ActiveRecord::Base) # Skip associations

        if model_class.column_names.include?(key.to_s)
          query = query.where(key => value)
        end
      end

      # Limit to recent objects to keep data fresh
      if model_class.column_names.include?("created_at")
        query = query.where("created_at > ?", 6.months.ago)
      end

      # Return a random matching object
      query.order("RANDOM()").first
    rescue NameError
      # If the model class doesn't exist, don't reuse
      nil
    end

    # Creates a new object using FactoryBot
    def create_new_object(factory_name, traits, attributes)
      if traits.any?
        FactoryBot.create(factory_name, *traits, **attributes)
      else
        FactoryBot.create(factory_name, **attributes)
      end
    end
  end
end
