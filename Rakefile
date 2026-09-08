# frozen_string_literal: true

require "rubygems"
require "rake"
require "rake/testtask"
require "rake/packagetask"
require "rubygems/package_task"
require "rspec/core"
require "rspec/core/rake_task"
require "spree/testing_support/extension_rake"
require "generators/spree/dummy/dummy_generator"

task default: [:spec]

# The dummy app is generated with Rails' own defaults. Every store that consumes
# this gem overrides two of them, and without the same overrides the suite tests
# a configuration nobody deploys.
#
# config.load_defaults 6.1 selects zeitwerk, which refuses to set up against the
# lib/**/ glob this engine puts on the autoload path and fails with "wrong
# constant name Solidus-adyen". The stores run load_defaults 5.0, and watg sets
# config.autoloader = :classic outright.
#
# belongs_to_required_by_default makes AdyenNotification#prev and #order
# mandatory, but an AUTHORISATION notification has neither by design - see the
# comment on the association. All three stores disable it in application.rb, in
# new_framework_defaults.rb, and again as Spree::Base.
#
# This hooks the generator step that writes config/application.rb, the only seam
# between the file being created and solidus:install booting the app.
module SolidusAdyenDummyAppConfig
  def test_dummy_config
    super

    path = File.expand_path("#{dummy_path}/config/application.rb", destination_root)
    return unless File.exist?(path)

    contents = File.read(path)
    return if contents.include?("config.autoloader")

    patched = contents.sub(/^([ \t]*)(config\.load_defaults .*)$/) do
      indent = Regexp.last_match(1)
      "#{indent}#{Regexp.last_match(2)}\n" \
        "#{indent}config.autoloader = :classic\n" \
        "#{indent}config.active_record.belongs_to_required_by_default = false"
    end
    raise "could not find config.load_defaults in #{path}" if patched == contents

    File.write(path, patched)
  end
end

Spree::DummyGenerator.prepend(SolidusAdyenDummyAppConfig)

desc "Generates a dummy app for testing"
task :test_app do
  ENV["LIB_NAME"] = "solidus-adyen"
  Rake::Task["extension:test_app"].invoke
end
