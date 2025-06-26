# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Validators::HbxEnrollments::HbxEnrollmentContract, type: :model, dbclean: :after_each do

  before :all do
    DatabaseCleaner.clean
  end

  it 'should be a container-ready operation' do
    expect(subject.respond_to?(:call)).to be_truthy
  end

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:special_enrollment_period) { FactoryBot.create(:special_enrollment_period, family: family, start_on: Date.today.beginning_of_year, end_on: Date.today + 2.days) }

  let(:enrollment_params) do
    { kind: 'individual',
      consumer_role_id: BSON::ObjectId.new,
      coverage_kind: 'health',
      effective_on: TimeKeeper.date_of_record,
      special_enrollment_period_id: special_enrollment_period.id,
      enrollment_kind: 'special_enrollment',
      hbx_enrollment_members: [{applicant_id: BSON::ObjectId.new,
                                is_subscriber: true,
                                eligibility_date: TimeKeeper.date_of_record,
                                coverage_start_on: TimeKeeper.date_of_record}]}
  end

  context 'success case' do
    before do
      @result = subject.call(enrollment_params)
    end

    it 'should return success' do
      expect(@result.success?).to be_truthy
    end

    it 'should not have any errors' do
      expect(@result.errors.empty?).to be_truthy
    end
  end

  context 'failure case' do
    context 'missing a mandatory attribute' do
      before do
        @result = subject.call(enrollment_params.except(:kind))
      end

      it 'should return failure' do
        expect(@result.failure?).to be_truthy
      end

      it 'should have any errors' do
        expect(@result.errors.empty?).to be_falsy
      end

      it 'should return error message' do
        expect(@result.errors.messages.first.text).to eq('is missing')
      end
    end

    context 'terminated_on falls before effective_on' do
      before do
        @result = subject.call(enrollment_params.merge!({terminated_on: TimeKeeper.date_of_record - 10.days}))
      end

      it 'should return failure with an error message' do
        expect(@result.errors.messages.first.text).to eq('must be on or after effective_on.')
      end
    end

    context 'bad object for terminated_on' do
      before do
        @result = subject.call(enrollment_params.merge!({terminated_on: 'test'}))
      end

      it 'should return failure with an error message' do
        expect(@result.errors.messages.first.text).to eq('must be a date')
      end
    end
  end
end
