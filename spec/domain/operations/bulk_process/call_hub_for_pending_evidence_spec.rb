# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe Operations::BulkProcess::CallHubForPendingEvidence, type: :model, dbclean: :after_each do
  let(:operation) { described_class.new }
  let(:params) { {} }

  context 'when there are eligible families' do
    let!(:person) { FactoryBot.create(:person, :with_consumer_role) }
    let!(:person2) do
      pr = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
      person.ensure_relationship_with(pr, 'spouse')
      pr
    end
    let!(:person3) do
      pr = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
      person.ensure_relationship_with(pr, 'child')
      pr
    end
    let!(:person4) do
      pr = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
      person.ensure_relationship_with(pr, 'child')
      pr
    end

    let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let!(:family_member2) { FactoryBot.create(:family_member, family: family, person: person2) }
    let!(:family_member3) { FactoryBot.create(:family_member, family: family, person: person3) }
    let!(:family_member4) { FactoryBot.create(:family_member, family: family, person: person4) }

    let!(:application) do
      FactoryBot.create(:financial_assistance_application,
                        family_id: family.id,
                        aasm_state: 'determined')
    end
    let!(:applicant) do
      FactoryBot.create(:financial_assistance_applicant,
                        application: application,
                        ssn: '987654321',
                        is_applying_coverage: false,
                        is_primary_applicant: true,
                        person_hbx_id: person.hbx_id,
                        first_name: person.first_name,
                        last_name: person.last_name)
    end

    let!(:applicant2) do
      FactoryBot.create(:financial_assistance_applicant,
                        application: application,
                        ssn: '987654322',
                        is_applying_coverage: false,
                        person_hbx_id: person2.hbx_id,
                        first_name: person2.first_name,
                        last_name: person2.last_name)
    end

    let!(:applicant3) do
      FactoryBot.create(:financial_assistance_applicant,
                        application: application,
                        ssn: '987654322',
                        citizen_status: 'us_citizen',
                        is_applying_coverage: true,
                        person_hbx_id: person3.hbx_id,
                        first_name: person3.first_name,
                        last_name: person3.last_name)
    end

    let!(:applicant4) do
      FactoryBot.create(:financial_assistance_applicant,
                        application: application,
                        ssn: '987654323',
                        is_applying_coverage: false,
                        person_hbx_id: person4.hbx_id,
                        first_name: person4.first_name,
                        last_name: person4.last_name)
    end
    let!(:individual_market_eligibility1) do
      applicant.build_ivl_eligibility_with_evidences
      applicant.save!
    end
    let!(:individual_market_eligibility2) do
      applicant2.build_ivl_eligibility_with_evidences
      applicant2.save!
    end
    let!(:individual_market_eligibility3) do
      applicant3.build_ivl_eligibility_with_evidences
      applicant3.save!
    end

    let!(:individual_market_eligibility4) do
      applicant4.build_ivl_eligibility_with_evidences
      applicant4.save!
    end

    before do
      family.update_attributes!(latest_application_gid: application.to_global_id.to_s, application_type: 'faa')
      applicant4.individual_market_eligibility.social_security_number_evidence.update!(current_state: 'verified')
    end

    it 'processes eligible applicants and generates CSV' do
      result = operation.call({ family_ids: [family.id], evidence_type: "social_security_number_evidence", reason_for_verification_request: "Bulk Hub Call for Pending Evidences: CRM 28618" })
      expect(result).to be_success
      log_files = Dir.glob("#{Rails.root}/bulk_evidences_hub_call_report*.csv")
      expect(log_files).to_not be_empty
    end
  end

  # after do
  #   log_files = Dir.glob("#{Rails.root}/bulk_evidences_hub_call_report*.csv")
  #   log_files.each { |file| File.delete(file) if File.exist?(file) }
  # end
end
