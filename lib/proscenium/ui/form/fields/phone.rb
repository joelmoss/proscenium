# frozen_string_literal: true

require 'phonelib'
require 'countries/iso3166'

module Proscenium::UI::Form::Fields
  class Phone < Base
    DEFAULT_COUNTRY = 'GB'

    def self.css_module_path
      source_path.sub_ext('.module.css')
    end

    register_element :phone_field, tag: 'phone-field'

    def template
      field :phone_field, class: :phone_field do
        label do
          label

          div class: :@inputs do
            div class: :@select do
              select name: '_phone_country_code', data: { unstyled: true } do
                countries.each do |name, code|
                  option(value: code, selected: code == country) { name }
                end
              end
              div data: { country_code: country.downcase }
              icon 'caret-down-solid'
            end

            input(name: field_name, type: 'text', **build_attributes)
          end

          hint
        end
      end
    end

    private

    def country
      @country ||= if value.blank?
                     DEFAULT_COUNTRY
                   else
                     Phonelib.parse(value, DEFAULT_COUNTRY).country || DEFAULT_COUNTRY
                   end
    end

    def countries
      ISO3166::Country.all_names_with_codes.to_h
    end
  end
end
