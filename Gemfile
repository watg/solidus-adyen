source "https://rubygems.org"

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end

# CI pins released Solidus versions rather than branch tips, because the
# stores that consume this gem run released gems. SOLIDUS_BRANCH still works
# for testing an unreleased branch by hand.
solidus_branch = ENV["SOLIDUS_BRANCH"].to_s
solidus_version = ENV["SOLIDUS_VERSION"].to_s
solidus_version = "~> 3.2.0" if solidus_branch.empty? && solidus_version.empty?

rails_version = ENV["RAILS_VERSION"].to_s
rails_version = "~> 6.1.0" if rails_version.empty?

gem "rails", rails_version
gem "rails-controller-testing", group: :test

# No Gemfile.lock is committed, so CI resolves from scratch every run and picks
# up gems the stores never see. Both bounds below are the versions all three
# store lockfiles already hold, and both are load-time failures, invisible to
# the resolver.
#
# concurrent-ruby 1.3.5 dropped the transitive require of "logger", which
# ActiveSupport 6.1 relies on, so boot raises
# "NameError: uninitialized constant ActiveSupport::LoggerThreadSafeLevel::Logger".
# watg/solidus_adyen already declares the same bound, which is why the stores
# lock 1.2.3 and no deploy hit this.
gem "concurrent-ruby", "< 1.3.5"

# state_machines 0.20 recurses forever through machine_collection.rb against
# the state_machines-activemodel 0.9 line Solidus 3.x resolves: saving a record
# whose state is mass assigned loops in around_validation. Unpinned, the suite
# reports 166 failures with 124 SystemStackError; bounded, 121 and none.
gem "state_machines", "< 0.7"

group :development, :test do
  if solidus_branch.empty?
    gem "solidus", solidus_version
  else
    gem "solidus", github: "solidusio/solidus", branch: solidus_branch
  end

  gem "solidus_auth_devise"

  gem "pg"
  gem "sqlite3", "~> 1.4"
end

group :test do
  gem "ffaker"
  gem "database_cleaner"
  gem "factory_bot"
  gem "timecop"
  gem "vcr"
  gem "webmock", "~> 1.24"
  gem "selenium-webdriver"
  gem "rspec_junit_formatter"
end

gemspec
