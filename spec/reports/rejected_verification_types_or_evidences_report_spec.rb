# frozen_string_literal: true

require 'csv'
require 'rails_helper'

describe RejectedVerificationTypesOrEvidencesReport, dbclean: :around_each do
  subject { described_class.new("rejected_verification_types_or_evidences_report", double(:current_scope => nil)) }

  # workaround for mongoid STI limitation - ensure _type field is available
  before(:all) do
    # force the _type field to be available for STI
    Eligibilities::V3::Eligibility.field :_type, type: String unless Eligibilities::V3::Eligibility.fields['_type']
  end

  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, assistance_year: TimeKeeper.date_of_record.year) }
  let(:applicant) do
    FactoryBot.create(:financial_assistance_applicant,
                      application: application,
                      dob: person.dob,
                      is_primary_applicant: true,
                      family_member_id: family.primary_applicant.id,
                      person_hbx_id: person.hbx_id)
  end

  let(:person2) { FactoryBot.create(:person, :with_consumer_role) }
  let!(:family2) { FactoryBot.create(:family, :with_primary_family_member, person: person2) }

  let(:individual_market_application) { FactoryBot.create(:individual_market_application, :determined, family_id: family2.id) }
  let(:im_applicant) { FactoryBot.create(:individual_market_applicant, application: individual_market_application, family_member_id: family2.family_members.first.id) }

  # create eligibilities/evidences at top level, need to do manually because of error with STI and embedded docs
  let!(:applicant_individual_market_eligibility) do
    applicant.eligibilities.create!(
      _type: 'Eligibilities::V3::IndividualMarketEligibility',
      key: :individual_market_eligibility,
      title: 'Individual Market Eligibility'
    )
  end

  let!(:applicant_aptc_csr_eligibility) do
    applicant.eligibilities.create!(
      _type: 'Eligibilities::V3::AptcCsrEligibility',
      key: :aptc_csr_eligibility,
      title: 'APTC/CSR Eligibility'
    )
  end

  let!(:im_applicant_individual_market_eligibility) do
    im_applicant.eligibilities.create!(
      _type: 'Eligibilities::V3::IndividualMarketEligibility',
      key: :individual_market_eligibility,
      title: 'Individual Market Eligibility'
    )
  end

  let!(:applicant_ssn_evidence) do
    applicant_individual_market_eligibility.evidences.create!(
      _type: 'Eligibilities::V3::Evidences::SocialSecurityNumberEvidence',
      key: :social_security_number_evidence,
      title: 'Social Security Number Evidence',
      current_state: :pending,
      is_satisfied: false
    )
  end

  let!(:applicant_esi_evidence) do
    applicant_aptc_csr_eligibility.evidences.create!(
      _type: 'FinancialAssistance::Evidences::EsiMecEvidence',
      key: :esi_mec_evidence,
      title: 'ESI MEC Evidence',
      current_state: :pending,
      is_satisfied: false
    )
  end

  let!(:applicant_income_evidence) do
    applicant_aptc_csr_eligibility.evidences.create!(
      _type: 'FinancialAssistance::Evidences::IncomeEvidence',
      key: :income_evidence,
      title: 'Income Evidence',
      current_state: :pending,
      is_satisfied: false
    )
  end

  let!(:im_applicant_citizenship_evidence) do
    im_applicant_individual_market_eligibility.evidences.create!(
      _type: 'Eligibilities::V3::Evidences::CitizenshipEvidence',
      key: :citizenship_evidence,
      title: 'Citizenship Evidence',
      current_state: :pending,
      is_satisfied: false
    )
  end

  let(:output_csv) { "#{Rails.root}/rejected_verification_types_or_evidences_report.csv" }

  before do
    [family, family2].each do |fam|
      fam.assign_latest_application_gid
      fam.save!
    end

    applicant_ssn_evidence.update(current_state: :rejected)
    applicant_esi_evidence.update(current_state: :rejected)
    applicant_income_evidence.update(current_state: :rejected)
    applicant.save!

    im_applicant_citizenship_evidence.update(current_state: :rejected)
    im_applicant.save!
  end

  after :each do
    File.delete(output_csv) if File.exist?(output_csv)
  end

  context '#application_family_ids' do
    it 'should return family ids with rejected evidences' do
      family_ids = subject.application_family_ids
      expect(family_ids).to include(family.id)
    end
  end

  context '#families' do
    it 'should return families with rejected evidences' do
      families = subject.families
      expect(families.pluck(:id)).to include(family.id)
      expect(families.pluck(:id)).to include(family2.id)
    end
  end

  context 'with multiple evidences from different types of applicants from different families' do
    before do
      subject.migrate
      @csv = CSV.read(output_csv)
    end

    it 'should include separate rows for each rejected evidence' do
      expect(@csv.size).to eq(5)
    end

    it 'should include details of person and evidence in the report' do
      esi_row = @csv.detect { |row| row[8]&.include?(l10n('faa.evidence_type_esi')) }
      expect(esi_row[7]).to eq(person.hbx_id)
      expect(esi_row[6]).to eq(application.hbx_id)
      expect(esi_row[8]).to eq(l10n('faa.evidence_type_esi'))

      income_row = @csv.detect { |row| row[8] == 'Income' }
      expect(income_row[7]).to eq(person.hbx_id)
      expect(income_row[6]).to eq(application.hbx_id)

      ssn_row = @csv.detect { |row| row[8] == 'Social Security Number' }
      expect(ssn_row[7]).to eq(person.hbx_id)
      expect(ssn_row[6]).to eq(application.hbx_id)

      citizenship_row = @csv.detect { |row| row[8] == 'Citizenship' }
      expect(citizenship_row[7]).to eq(person2.hbx_id)
      expect(citizenship_row[6]).to eq(individual_market_application.hbx_id)
    end
  end
end