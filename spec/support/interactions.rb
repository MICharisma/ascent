require "rails_jsdom"

# Interaction specs drive real pages, with their Stimulus controllers and Turbo,
# in jsdom instead of a browser. rails-jsdom ships a Minitest base class; this
# module gives an RSpec request example group the same setup and teardown.
module InteractionExampleGroup
  extend ActiveSupport::Concern
  include ActiveSupport::Testing::TimeHelpers
  include RailsJsdom::TestHelper

  # An app without Action Cable configured has no pubsub to take over.
  CABLE = ActionCable.server.config.cable.present?

  included do
    before do
      rails_jsdom_clock
      rails_jsdom_take_over_pubsub if CABLE
    end

    after do
      RailsJsdom.bridge.reset
      if CABLE
        rails_jsdom_close_cables
        rails_jsdom_restore_pubsub
      end
    end
  end

  # Pages run their timers on the test's clock, so `travel 2.seconds` fires a
  # timer due in 1.5. Keep the microseconds, or the jump can come up short.
  def travel(duration, with_usec: true, &) = super
end

# `expect(page).to have_css(...)` and friends, read from the settled page by
# rails-jsdom's own assertions so failures keep its messages. `not_to` uses the
# matching `assert_no_*`. They work on `page` and on found elements.
module InteractionMatchers
  ASSERTIONS = {
    have_css: :selector, have_selector: :selector, have_content: :text, have_text: :text,
    have_field: :field, have_button: :button, have_link: :link, have_current_path: :current_path, have_title: :title
  }.freeze

  ASSERTIONS.each do |matcher, assertion|
    define_method(matcher) { |*arguments, **options| Assertion.new(assertion, arguments, options) }
    define_method(matcher.to_s.sub("have_", "have_no_")) { |*arguments, **options| Assertion.new(assertion, arguments, options).negated }
  end

  class Assertion
    include RSpec::Matchers::Composable

    attr_reader :failure_message, :failure_message_when_negated

    def initialize(assertion, arguments, options, negated: false)
      @assertion, @arguments, @options, @negated = assertion, arguments, options, negated
    end

    def negated = self.class.new(@assertion, @arguments, @options, negated: true)
    def matches?(actual) = @negated ? meets?(actual, "assert_no") : meets?(actual, "assert")
    def does_not_match?(actual) = @negated ? meets?(actual, "assert") : meets?(actual, "assert_no")
    def description = "have #{@assertion} #{@arguments.map(&:inspect).join(", ")}"

    private

    def meets?(actual, prefix)
      assertion = "#{prefix}_#{@assertion}"
      if actual.respond_to?(assertion)
        actual.public_send(assertion, *@arguments, **@options)
      else
        # Elements answer only text and selector assertions; scope the rest.
        test = actual.instance_variable_get(:@test)
        test.within(actual) { test.public_send(assertion, *@arguments, **@options) }
      end
      true
    rescue Minitest::Assertion => failure
      @failure_message = @failure_message_when_negated = failure.message
      false
    end
  end

  # `have_select "League", selected: "MLB", options: [...]`, by option text.
  # rails-jsdom's `have_field ..., with:` compares the select's value instead.
  def have_select(locator, selected: nil, options: nil, with_options: nil)
    RSpec::Matchers::BuiltIn::Satisfy.new("have select #{locator.inspect}") do |actual|
      field = actual.find_field(locator, type: "select")
      choices = field.evaluate_script("Array.from(this.options).map(option => [option.text.trim(), option.selected])")
      (selected.nil? || choices.select(&:last).map(&:first) == Array(selected)) &&
        (options.nil? || choices.map(&:first) == options) &&
        (with_options.nil? || (with_options - choices.map(&:first)).empty?)
    rescue RailsJsdom::Error
      false
    end
  end
end

RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/spec/interactions/}) { |metadata| metadata[:type] = :interaction }
  config.include RSpec::Rails::RequestExampleGroup, type: :interaction
  config.include InteractionExampleGroup, type: :interaction
  config.include InteractionMatchers, type: :interaction
  config.include Devise::Test::IntegrationHelpers, type: :interaction
end
