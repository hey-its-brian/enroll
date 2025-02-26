# frozen_string_literal: true

require 'rails_helper'

describe Queries::AssisterAgencyDatatableQuery, dbclean: :after_each do
  subject { Queries::AssisterAgencyDatatableQuery.new({}, data_store: Effective::Datatables::DataStores::AssisterFamilyCountDataStore) }

  context "default query" do
    it "builds scope with selector for assisters" do
      expect(subject.build_scope.selector).to eq({"profiles._type" => /.*AssisterAgencyProfile$/})
    end

    context "is paginated" do
      let!(:skip) { 64 }
      let!(:limit) { 4 }
      before { subject.skip(skip).limit(limit) }

      it "builds query with pagination" do
        expect(subject.build_query.options).to eq(skip: skip, limit: limit)
      end
    end
  end

  context "search" do
    shared_examples "builds scope with selector for search query" do |assister_name_search_flag_enabled:|
      before do
        subject.instance_variable_set(:@search_string, search_query)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:sensor_tobacco_carrier_usage).and_return(false)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:broker_table_staff_name_search).and_return(assister_name_search_flag_enabled)
      end

      it "builds scope with selector for search query" do
        expect(subject.build_scope.selector).to eq(
          {
            "profiles._type" => /.*AssisterAgencyProfile$/,
            "$or" => [
              {"legal_name" => /#{search_query}/i},
              {"fein" => /#{search_query}/i},
              {"hbx_id" => /#{search_query}/i},
              {"profiles._id" => {"$in" => assister_name_search_flag_enabled ? [profile.id] : []}}
            ]
          }
        )
      end
    end

    let!(:search_query) { "test_search_query" }
    let!(:profile) do
      profile = FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile)
      FactoryBot.create(
        :person,
        first_name: search_query, # test search using first_name of the person with assister role in assister_agency_profile
        assister_agency_staff_roles: [FactoryBot.create(:assister_agency_staff_role, assister_agency_profile: profile)]
      )
      profile
    end

    it_behaves_like "builds scope with selector for search query", assister_name_search_flag_enabled: true
    it_behaves_like "builds scope with selector for search query", assister_name_search_flag_enabled: false
  end

  context "order" do
    shared_examples "by field" do |field, order|
      def create_organization(legal_name, family_count)
        org = FactoryBot.create(
          :benefit_sponsors_organizations_general_organization,
          :with_assister_agency_profile,
          legal_name: legal_name,
          site: FactoryBot.create(
            :benefit_sponsors_site,
            :with_benefit_market,
            :as_hbx_profile,
            site_key: ::EnrollRegistry[:enroll_app].settings(:site_key).item
          )
        )

        (0...family_count).each do
          family = FactoryBot.create(:family, :with_primary_family_member, person: FactoryBot.create(:person))
          family.assister_agency_accounts.create!(benefit_sponsors_assister_agency_profile_id: org.assister_agency_profile.id, start_on: TimeKeeper.date_of_record, is_active: true)
        end

        org
      end

      let!(:organization_0) { create_organization("A", 0) }
      let!(:organization_1) { create_organization("B", 1) }
      let!(:organization_2) { create_organization("C", 2) }
      let!(:organization_3) { create_organization("D", 3) }

      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:broker_family_count).and_return(true)
        Effective::Datatables::DataStores::AssisterFamilyCountDataStore.setup # setup the cache after the Families have been created
        subject.order_by({field => order})
      end

      it "builds query with #{order == :asc ? 'ascending' : 'descending'} order by #{field}" do
        expected_order = [organization_0, organization_1, organization_2, organization_3]
        expected_order.reverse! if order == :desc
        query = subject.build_query
        if field == "legal_name"
          expect(query.class).to eq(Mongoid::Criteria)
          expect(query.options[:sort]).to eq({field.to_s => order == :asc ? 1 : -1})
        else
          expect(query.class).to eq(Array)
        end
        expect(query.to_a).to eq(expected_order)
      end
    end

    %w[legal_name active_families_count].each do |field|
      context "by #{field}" do
        %i[asc desc].each do |order|
          it_behaves_like "by field", field, order
        end
      end
    end
  end
end
