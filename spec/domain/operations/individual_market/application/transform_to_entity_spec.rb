# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::Application::TransformToEntity, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_ssn, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }

  let(:renewal_application) { FactoryBot.create(:individual_market_application, :initial, :renewal, family_id: family.id) }
  let(:renewal_applicant) { FactoryBot.create(:individual_market_applicant, :with_person_name, application: renewal_application, family_member_id: primary_applicant.id) }
  let(:renewal_demographics) do
    demo = FactoryBot.create(:individual_market_demographics, applicant: renewal_applicant)
    renewal_applicant.build_individual_market_eligibility
    renewal_applicant.build_individual_market_evidences
    renewal_applicant.build_aptc_csr_eligibility
    renewal_applicant.save!
    demo
  end

  let(:application) do
    current_application
    family.latest_application_gid = current_application.to_global_id.uri.to_s
    family.save!
    renewal_app = ::Operations::IndividualMarket::Applications::Renewals::SubmitAndDetermine.new.call(
      application_id: renewal_demographics.applicant.application.id
    ).success

    renewal_app.applicants.each do |appli|
      appli.eligibilities.each do |eligibility|
        eligibility.evidences.each do |evidence|
          evidence.determined_at = DateTime.now
        end
      end
    end
    renewal_app.save!
    renewal_app
  end

  let(:current_application) do
    application = FactoryBot.create(:individual_market_application, :determined, family_id: family.id)
    applicant = FactoryBot.create(:individual_market_applicant, :with_person_name, application: application, family_member_id: primary_applicant.id)
    FactoryBot.create(:individual_market_demographics, applicant: applicant)
    applicant.build_individual_market_eligibility
    applicant.build_individual_market_evidences
    applicant.individual_market_eligibility.evidences.each_with_index do |evidence, index|
      index.even? ? evidence.mark_as_outstanding : evidence.mark_as_verified
    end
    application.save!
    application
  end

  describe '#call' do
    context 'when: application is a valid renewal application' do
      it 'returns a success result' do
        expect(subject.call(application)).to be_success
      end
    end

    context 'when: application is a valid non-renewal application' do
      it 'returns a success result' do
        expect(subject.call(current_application)).to be_success
      end
    end

    context 'with a malformed cv3' do
      before do
        allow(application).to receive(:applicants).and_return(nil)
      end

      it 'raises an error' do
        result = described_class.new.call(application)

        expect(result).to be_failure
      end
    end
  end
end
