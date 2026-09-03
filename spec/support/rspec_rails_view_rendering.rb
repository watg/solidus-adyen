# rspec-rails 3.x stubs out view rendering in controller specs by rebuilding
# every template it resolves, and it builds them the way Rails 5 did: with
# `formats`, and without `locals`. Rails 6 renamed `ActionView::Template#formats`
# to `format` and made `locals` a required keyword, so any controller spec that
# renders a template blows up with `undefined method 'formats'`.
#
# Backport how rspec-rails 4 builds those templates, so views stay stubbed
# instead of the example erroring out. Drop this once the gem's rspec-rails
# dependency moves to 4.x.
if Gem.loaded_specs["rspec-rails"].version < Gem::Version.new("4") &&
    !ActionView::Template.method_defined?(:formats)
  module RSpec
    module Rails
      module ViewRendering
        class EmptyTemplateResolver
          def self.nullify_template_rendering(templates)
            templates.map do |template|
              ::ActionView::Template.new(
                "",
                template.identifier,
                EmptyTemplateHandler,
                :virtual_path => template.virtual_path,
                :format => template.format,
                :locals => [])
            end
          end
        end

        class EmptyTemplateHandler
          def self.call(_template, _source = nil)
            ::Rails.logger.info("  Template rendering was prevented by rspec-rails. Use `render_views` to verify rendered view contents if necessary.")

            %("")
          end
        end
      end
    end
  end
end
