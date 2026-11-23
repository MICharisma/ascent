# Coverage is opt-in: COVERAGE=1 bundle exec rspec, then open coverage/index.html.
return unless ENV["COVERAGE"]

require "simplecov"

SimpleCov.start "rails" do
  enable_coverage :branch
  add_filter %w[/spec/ /config/ /vendor/]
  add_group "Components", "app/views/components"
  add_group "Services", "app/services"
  add_group "Policies", "app/policies"
end
