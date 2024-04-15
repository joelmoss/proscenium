# frozen_string_literal: true

require 'phonelib'
require 'countries/iso3166'

module Proscenium::UI::Form::Fields
  class Tel < Base
    DEFAULT_COUNTRY = 'GB'

    sideload_assets js: { type: 'module' }

    register_element :pui_tel_field

    def view_template
      field :pui_tel_field do
        label do
          div part: :inputs do
            div part: :country do
              select name: '_phone_country_code' do
                countries.each do |name, code|
                  option(value: code, selected: code == country) { name }
                end
              end
            end

            input(name: field_name, type: 'text', part: :number, **build_attributes)
          end
        end

        hint
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
