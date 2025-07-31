# frozen_string_literal: true

# shared context for setting up both DMF application types
RSpec.shared_context 'dual applications with eligible family setup' do
  let(:encrypted_ssn) { SymmetricEncryption.encrypt(221_021_014) }
  let(:encrypted_ssn2) { SymmetricEncryption.encrypt(221_031_015) }
  let!(:hbx_profile) { FactoryBot.create(:hbx_profile) }
  let!(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
  let(:dob) { Date.today - 55.years }

  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: primary_person) }
  let(:primary_person) { FactoryBot.create(:person, :with_consumer_role, dob: dob, ssn: 221_021_014) }
  let(:non_primary_person) { FactoryBot.create(:person, :with_consumer_role, dob: dob, ssn: 221_031_015) }
  let!(:non_primary_family_member) { FactoryBot.create(:family_member, person: non_primary_person, family: family) }

  before do
    allow(EnrollRegistry[:qhp_application].feature).to receive(:is_enabled).and_return(true)
    allow(Family).to receive(:find_by).and_return(family)
    job.create_process_status if defined?(job) && job.present?
    BenefitMarkets::Products::ProductRateCache.initialize_rate_cache!

    current_application.build_aptc_eligibilities_evidences if current_application.is_a? FinancialAssistance::Application
    current_application.build_ivl_eligibility_with_evidences
    current_application.save!

    allow(family).to receive(:latest_application).and_return(current_application)
    Operations::Eligibilities::BuildFamilyDetermination.new.call({effective_date: Date.today, family: family})
  end

  # helper methods to create different application types
  def create_financial_assistance_application
    application_hbx_id = @application_hbx_id.present? ? @application_hbx_id : '233268974330342344325'
    FactoryBot.create(:financial_assistance_application, family_id: family.id, hbx_id: application_hbx_id, applicants: [
      FactoryBot.create(
        :financial_assistance_applicant,
        first_name: primary_person.first_name,
        last_name: primary_person.last_name,
        gender: primary_person.gender,
        dob: primary_person.dob,
        person_hbx_id: primary_person.hbx_id,
        is_applying_coverage: true,
        citizen_status: 'us_citizen',
        no_ssn: '0',
        encrypted_ssn: encrypted_ssn,
        family_member_id: family.primary_family_member.id,
        is_primary_applicant: true
      ),
      FactoryBot.create(
        :financial_assistance_applicant,
        first_name: non_primary_person.first_name,
        last_name: non_primary_person.last_name,
        gender: non_primary_person.gender,
        dob: non_primary_person.dob,
        person_hbx_id: non_primary_person.hbx_id,
        is_applying_coverage: true,
        citizen_status: 'us_citizen',
        no_ssn: '0',
        encrypted_ssn: encrypted_ssn2,
        family_member_id: non_primary_family_member.id
      )
    ])
  end

  def create_individual_market_application
    application_hbx_id = @application_hbx_id.present? ? @application_hbx_id : '23326897257302344325'
    app = FactoryBot.create(:individual_market_application,
                            :determined,
                            hbx_id: application_hbx_id,
                            family: family,
                            applicants: [
                              FactoryBot.build(:individual_market_applicant,
                                               :with_demographics,
                                               :with_eligibilities,
                                               :with_phone_number,
                                               :with_email,
                                               family_member_id: family.primary_family_member.id,
                                               is_primary_applicant: true,
                                               person_name: {
                                                 given_name: primary_person.first_name,
                                                 family_name: primary_person.last_name
                                               }),
                              FactoryBot.build(:individual_market_applicant,
                                               :with_demographics,
                                               :with_eligibilities,
                                               :with_phone_number,
                                               :with_email,
                                               family_member_id: non_primary_family_member.id,
                                               is_primary_applicant: false,
                                               person_name: {
                                                 given_name: non_primary_person.first_name,
                                                 family_name: non_primary_person.last_name
                                               })
                            ])
    app.applicants.first.demographics.update!(encrypted_ssn: encrypted_ssn, no_ssn: false)
    app.applicants.last.demographics.update!(encrypted_ssn: encrypted_ssn2, no_ssn: false)
    FactoryBot.create(:individual_market_immigration_information, applicant: app.applicants.first)
    FactoryBot.create(:individual_market_immigration_information, applicant: app.applicants.last)
    app.save!
    app
  end
end