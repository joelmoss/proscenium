# frozen_string_literal: true

module UI
  class FormController < UIController
    add_breadcrumb 'Form', :ui_form

    def text_field = add_breadcrumb 'Text Field', :ui_form_text_field
    def file_field = add_breadcrumb 'File Field', :ui_form_file_field
    def url_field = add_breadcrumb 'URL Field', :ui_form_url_field
    def email_field = add_breadcrumb 'Email Field', :ui_form_email_field
    def number_field = add_breadcrumb 'Number Field', :ui_form_number_field
    def time_field = add_breadcrumb 'Time Field', :ui_form_time_field
    def date_field = add_breadcrumb 'Date Field', :ui_form_date_field
    def datetime_local_field = add_breadcrumb 'Datetime Local Field', :ui_form_datetime_local_field
    def week_field = add_breadcrumb 'Week Field', :ui_form_week_field
    def month_field = add_breadcrumb 'Month Field', :ui_form_month_field
    def color_field = add_breadcrumb 'Color Field', :ui_form_color_field
    def search_field = add_breadcrumb 'Search Field', :ui_form_search_field
    def password_field = add_breadcrumb 'Password Field', :ui_form_password_field
    def range_field = add_breadcrumb 'Range Field', :ui_form_range_field
    def tel_field = add_breadcrumb 'Tel Field', :ui_form_tel_field
    def checkbox_field = add_breadcrumb 'Checkbox Field', :ui_form_checkbox_field
    def select_field = add_breadcrumb 'Select Field', :ui_form_select_field
    def radio_group = add_breadcrumb 'Radio Group', :ui_form_radio_group
    def radio_field = add_breadcrumb 'Radio Field', :ui_form_radio_field
    def textarea_field = add_breadcrumb 'Textarea Field', :ui_form_textarea_field
    def rich_textarea_field = add_breadcrumb 'Rich Textarea Field', :ui_form_rich_textarea_field
    def hidden_field = add_breadcrumb 'Hidden Field', :ui_form_hidden_field
  end
end
