# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::Renew, dbclean: :after_each do

  describe '#call' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:primary_applicant) { family.primary_applicant }
    let(:fa_application) do
      FactoryBot.create(
        :financial_assistance_application,
        assistance_year: fa_assistance_year,
        family_id: family.id,
        years_to_renew: 5
      )
    end

    let(:qhp_application) { FactoryBot.create(:individual_market_application, assistance_year: qhp_assistance_year, family_id: family.id) }
    let(:current_year) { TimeKeeper.date_of_record.year }
    let(:renewal_year) { current_year.next }
    let(:previous_year) { current_year.pred }

    let(:hbx_profile)   { FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period) }
    let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }

    before :each do
      benefit_sponsorship
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:skip_eligibility_redetermination).and_return(false)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
    end

    context 'when:
      - the QHP application feature is enabled
      - family does not have applications of any type
      ' do

      before do
        primary_applicant
      end

      it 'returns failure' do
        expect(
          subject.call({ family_id: family.id, renewal_year: renewal_year }).failure
        ).to eq("Family #{family.id} does not have a latest application")
      end
    end

    context 'when:
      - the QHP application feature is enabled
      - family has applications of QHP type for previous year
      ' do

      let(:qhp_assistance_year) { previous_year }

      before do
        qhp_application
        family.latest_application_gid = qhp_application.to_global_id.uri.to_s
        family.save!
      end

      it 'returns failure' do
        expect(
          subject.call({ family_id: family.id, renewal_year: renewal_year }).failure
        ).to eq("Family #{family.id} is not eligible for FAA renewal. Latest application type: qhp")
      end
    end

    context 'when:
      - the QHP application feature is enabled
      - family has applications of FAA type for previous year
      ' do

      let(:fa_assistance_year) { previous_year }

      before do
        fa_application
        family.latest_application_gid = fa_application.to_global_id.uri.to_s
        family.save!
      end

      it 'returns failure' do
        expect(
          subject.call({ family_id: family.id, renewal_year: renewal_year }).failure
        ).to eq("Family #{family.id} does not have a latest application for current year: #{renewal_year.pred}")
      end
    end

    context 'when:
      - the QHP application feature is enabled
      - family has a QHP application for current year
      ' do

      let(:qhp_assistance_year) { current_year }

      before do
        qhp_application
        family.latest_application_gid = qhp_application.to_global_id.uri.to_s
        family.save!
      end

      it 'returns failure' do
        expect(
          subject.call({ family_id: family.id, renewal_year: renewal_year }).failure
        ).to eq(
          "Family #{family.id} is not eligible for FAA renewal. Latest application type: qhp"
        )
      end
    end
  end
end
