# frozen_string_literal: true

require 'rails_helper'

describe Queries::IdentityVerificationDatatableQuery, dbclean: :after_each do
  let!(:person_with_pending_identity) do
    FactoryBot.create(:person, :with_consumer_role, first_name: 'John', last_name: 'Doe').tap do |p|
      p.consumer_role.update_attributes(identity_validation: :pending)
    end
  end

  let!(:person_with_approved_validations) do
    FactoryBot.create(:person, :with_consumer_role, first_name: 'Robert', last_name: 'Jones').tap do |p|
      p.consumer_role.update_attributes(identity_validation: :valid, application_validation: :valid)
    end
  end

  subject { described_class.new({}) }

  describe '#initialize' do
    it 'sets custom attributes' do
      attributes = { 'option' => 'value' }
      query = described_class.new(attributes)
      expect(query.custom_attributes).to eq(attributes)
    end
  end

  describe '#datatable_search' do
    it 'sets the search_string' do
      query = subject.datatable_search('John')
      expect(query.search_string).to eq('John')
    end

    it 'returns self for chaining' do
      expect(subject.datatable_search('test')).to eq(subject)
    end
  end

  describe '#build_scope' do
    context 'when feature flag is enabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_people_with_no_evidence).and_return(true)
      end

      it 'uses identity_verifications_table_query' do
        expect(subject).to receive(:identity_verifications_table_query).and_call_original
        subject.build_scope
      end
    end

    context 'when feature flag is disabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_people_with_no_evidence).and_return(false)
        allow(Person).to receive(:for_admin_approval_with_documents).and_return(Person.all)
      end

      it 'uses Person.for_admin_approval_with_documents' do
        expect(Person).to receive(:for_admin_approval_with_documents).and_return(Person.all)
        subject.build_scope
      end
    end

    context 'when search string is blank' do
      before do
        subject.datatable_search('')
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_people_with_no_evidence).and_return(true)
        allow(subject).to receive(:identity_verifications_table_query).and_return(Person.all)
      end

      it 'returns the base scope without filtering' do
        expect(subject.build_scope).to eq(Person.all)
      end
    end

    context 'when search string is too short' do
      before do
        subject.datatable_search('a')
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_people_with_no_evidence).and_return(true)
        allow(subject).to receive(:identity_verifications_table_query).and_return(Person.all)
      end

      it 'returns the base scope without filtering' do
        expect(subject.build_scope).to eq(Person.all)
      end
    end

    context 'when search string is valid' do
      before do
        subject.datatable_search('John')
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_people_with_no_evidence).and_return(true)
        allow(subject).to receive(:identity_verifications_table_query).and_return(Person.all)
        allow(Person).to receive(:search).with('John').and_return(Person.where(first_name: 'John'))
      end

      it 'filters by search results' do
        expect(Person).to receive(:search).with('John').and_return(Person.where(first_name: 'John'))
        subject.build_scope
      end
    end
  end

  describe '#identity_verifications_table_query' do
    it 'returns people with pending/rejected identity or application validation' do
      # Mock the aggregation results
      allow(Person.collection).to receive(:aggregate).and_return([
                                                                   { "_id" => person_with_pending_identity.id }
                                                                 ])

      result = subject.identity_verifications_table_query
      expect(result).to be_a(Mongoid::Criteria)
      expect(result.selector).to include("_id" => { "$in" => [person_with_pending_identity.id] })
    end
  end

  describe '#order_by' do
    it 'sets the order_by instance variable' do
      subject.order_by('name')
      expect(subject.instance_variable_get(:@order_by)).to eq('name')
    end

    it 'returns self for chaining' do
      expect(subject.order_by('name')).to eq(subject)
    end
  end

  describe '#skip' do
    it 'sets the skip instance variable' do
      subject.skip(10)
      expect(subject.instance_variable_get(:@skip)).to eq(10)
    end

    it 'returns self for chaining' do
      expect(subject.skip(10)).to eq(subject)
    end
  end

  describe '#limit' do
    it 'sets the limit instance variable' do
      subject.limit(25)
      expect(subject.instance_variable_get(:@limit)).to eq(25)
    end

    it 'returns self for chaining' do
      expect(subject.limit(25)).to eq(subject)
    end
  end

  describe '#klass' do
    it 'returns the Person class' do
      expect(subject.klass).to eq(Person)
    end
  end

  describe '#size' do
    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_people_with_no_evidence).and_return(true)
    end

    it 'returns the count of records in scope' do
      scope = double(count: 42)
      allow(subject).to receive(:build_scope).and_return(scope)
      expect(subject.size).to eq(42)
    end
  end

  describe '#identity_verifications_table_query' do
    let!(:person_with_pending_identity) do
      FactoryBot.create(:person, :with_consumer_role, first_name: 'John', last_name: 'Doe').tap do |p|
        p.consumer_role.update_attributes(identity_validation: :pending)
      end
    end

    let!(:person_with_pending_application) do
      FactoryBot.create(:person, :with_consumer_role, first_name: 'Jane', last_name: 'Smith').tap do |p|
        p.consumer_role.update_attributes(identity_validation: :valid, application_validation: :pending)
      end
    end

    context 'when application_validation_in_identity_verification feature is enabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:application_validation_in_identity_verification).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_people_with_no_evidence).and_return(true)
        allow(Person.collection).to receive(:aggregate).and_return([
                                                                     { "_id" => person_with_pending_identity.id },
                                                                     { "_id" => person_with_pending_application.id }
                                                                   ])
      end

      it 'includes people with pending/rejected identity or application validation' do
        result = subject.identity_verifications_table_query
        expect(result).to be_a(Mongoid::Criteria)
        expected_ids = [person_with_pending_identity.id, person_with_pending_application.id]
        expect(result.selector["_id"]["$in"]).to match_array(expected_ids)
      end
    end

    context 'when application_validation_in_identity_verification feature is disabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:application_validation_in_identity_verification).and_return(false)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_people_with_no_evidence).and_return(true)
        allow(Person.collection).to receive(:aggregate).and_return([
                                                                     { "_id" => person_with_pending_identity.id }
                                                                   ])
      end

      it 'only includes people with pending/rejected identity validation' do
        result = subject.identity_verifications_table_query
        expect(result).to be_a(Mongoid::Criteria)
        expect(result.selector["_id"]["$in"]).to match_array([person_with_pending_identity.id])
        expect(result.selector["_id"]["$in"]).not_to include(person_with_pending_application.id)
      end
    end
  end
end
