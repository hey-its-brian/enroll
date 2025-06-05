# frozen_string_literal: true

module Effective
  module Datatables
    # datatable for displaying all people
    class PeopleDataTable < Effective::MongoidDatatable
      include ApplicationHelper
      include HtmlScrubberUtil
      include DropdownHelper
      include ::ResourceRegistryHelper

      datatable do
        table_column :name, :label => l10n('hbx_profiles.people.table.name'), :proc => proc { |row| row.full_name }, :filter => false, :sortable => false
        table_column :dob, :label => l10n('hbx_profiles.people.table.dob'), :proc => proc { |row| row.dob }, :filter => false, :sortable => false
        table_column :hbx_id, :label => l10n('hbx_profiles.people.table.hbx_id'), :proc => proc { |row| row.hbx_id }, :filter => false, :sortable => false
        table_column :role_type, :label => l10n('hbx_profiles.people.active_roles'), :proc => proc { |row| all_roles(row) }, :filter => false, :sortable => false
        table_column :actions, :label => l10n('actions'), :width => '50px', :proc => proc { |row|
          dropdown = [
            [sanitize_html("<div class='#{pundit_class(Family, :can_update_ssn?)}'> Edit DOB / SSN </div>"), edit_dob_ssn_path(id: row.id, row_actions_id: "person_actions_#{row.id}"),
             can_display_edit_dob_ssn?(row, pundit_allow(Family, :can_update_ssn?))]
          ]

          render partial: 'datatables/shared/dropdown', locals: {dropdowns: map_legacy_dropdown(dropdown), row_actions_id: "person_actions_#{row.id}"}, formats: :html
        }, :filter => false, :sortable => false
      end

      def collection
        @people = Queries::PeopleDatatableQuery.new(attributes) unless (defined? @people) && @people.present?
        @people
      end

      def all_roles(person)
        person.all_active_role_names.join(', ')
      end

      # Determines if the edit DOB/SSN action should be enabled or disabled based on the person's family status and the QHP application feature flag.
      #
      # @param person [Person] the person object
      # @param allow [Boolean] whether the action is allowed
      #
      # @return [String] 'disabled' or 'ajax' based on the conditions
      def can_display_edit_dob_ssn?(person, allow)
        return 'disabled' unless allow

        if qhp_application_feature_enabled?
          person.has_an_active_family_member? ? 'disabled' : 'ajax'
        else
          return 'ajax' if person.families.present?

          'disabled'
        end
      end

      def global_search?
        true
      end

      def authorized?(current_user, _controller, _action, _resource)
        current_user.has_hbx_staff_role?
      end
    end
  end
end
