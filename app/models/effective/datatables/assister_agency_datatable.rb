# frozen_string_literal: true

module Effective
  module Datatables
    # Datatable class for AssisterAgency
    class AssisterAgencyDatatable < Effective::MongoidDatatable
      DATA_STORE = Effective::Datatables::DataStores::AssisterFamilyCountDataStore # data store for assister family count

      datatable do
        table_column :legal_name, :label => l10n('legal_name'), :proc => proc { |row|
                                                                           link_to h(row.legal_name), benefit_sponsors.profiles_assister_agencies_assister_agency_profile_path(row.assister_agency_profile)
                                                                         }, :sortable => true, :filter => false, :width => '30%'
        table_column(:active_families_count, :label => l10n('families_count'), :proc => proc { |row| DATA_STORE.fetch_field(row) }, :sortable => true, :filter => false, :width => '20%') if EnrollRegistry.feature_enabled?(:broker_family_count)
        # table_column :assister_org_id, :label => l10n('assister_org_id'), :proc => proc { |row| row.assister_agency_profile.inspect }, :sortable => false, :filter => false, :width => '10%'
        default_order :legal_name, :asc
      end

      def collection
        @collection ||= Queries::AssisterAgencyDatatableQuery.new(attributes, data_store: DATA_STORE)
      end

      def global_search?
        true
      end

      def nested_filter_definition
        return nil if EnrollRegistry.feature_enabled?(:bs4_admin_flow)
        {
          assister_agencies:
            [
              {scope: 'all', label: l10n('all')}
            ],
          top_scope: :assister_agencies
        }
      end

      def authorized?(current_user, _controller, _action, _resource)
        current_user.has_hbx_staff_role?
      end
    end
  end
end
