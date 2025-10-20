# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::Applications::Renewals::GenerateQhpRenewalApplicationsReport, dbclean: :after_each do
  let(:csv_report_headers) do
    [
      "PrimaryHbxId",
      "ApplicationHbxId",
      "AllApplicantHbxIds",
      "ApplicationStatus (CurrentState)",
      "IndividualApplicantEligibilities",
      "IndividualApplicantIneligibilityReasons"
    ]
  end

  let(:person) { FactoryBot.create(:person, :with_ssn, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }
  let(:file_path) { "#{Rails.root}/qhp_renewal_application_report_#{TimeKeeper.date_of_record.strftime('%m_%d_%Y')}.csv" }
  let(:assistance_year) { TimeKeeper.date_of_record.year.next }

  let(:current_application) do
    application = FactoryBot.create(:individual_market_application, :determined, family_id: family.id, assistance_year: assistance_year.pred)
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

  let(:renewal_applicant) { FactoryBot.create(:individual_market_applicant, :with_person_name, family_member_id: primary_applicant.id) }
  let(:renewal_application) do
    app = FactoryBot.create(:individual_market_application, :initial, :renewal, family_id: family.id, assistance_year: assistance_year, applicants: [renewal_applicant])
    FactoryBot.create(:individual_market_demographics, applicant: renewal_applicant)
    renewal_applicant.build_individual_market_eligibility
    renewal_applicant.build_individual_market_evidences
    renewal_applicant.build_aptc_csr_eligibility
    renewal_applicant.save!
    app.save!
    app
  end

  describe '#call' do
    context 'when: renewal script has been triggered for next year' do

      before do
        current_application
        family.latest_application_gid = current_application.to_global_id.uri.to_s
        renewal_application
        family.save!

        ::Operations::IndividualMarket::Applications::Renewals::SubmitAndDetermine.new.call(application_id: renewal_application.id)
        renewal_application.reload
        @result = subject.call(assistance_year: assistance_year)
      end

      it 'returns a success result' do
        expect(@result).to be_a_success
      end

      it 'generates a CSV' do
        expect(File.exist?(file_path)).to be_truthy
      end

      it 'the CSV includes reasons for ineligible applicants' do
        csv_contents = CSV.read(file_path)

        headers = csv_contents[0]
        expect(headers).to eq csv_report_headers

        row = csv_contents[1]
        expect(row[0]).to eq person.hbx_id
        expect(row[1]).to eq renewal_application.hbx_id
        expect(row[2]).to eq renewal_application.applicants.map(&:hbx_id).join("\n")
        expect(row[3]).to eq "determined"

        hbx_id = renewal_application.applicants.first.hbx_id
        expect(row[4]).to eq "#{hbx_id}: QHP Ineligible"
        expect(row[5]).to eq "#{hbx_id}: Applicant is not a resident"
      end

      after { File.delete(file_path) if File.exist?(file_path) }
    end
  end
end
