# frozen_string_literal: true

RSpec.describe Operations::Eligibilities::Evidences::Show, type: :operation do
  let(:user) { FactoryBot.create(:user, person: person) }
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_family_member }

  let(:faa_application) do
    FactoryBot.create(
      :financial_assistance_application,
      family_id: family.id,
      aasm_state: 'determined',
      submitted_at: Time.now,
      assistance_year: TimeKeeper.date_of_record.year
    )
  end

  let(:applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      family_member_id: primary_applicant.id,
      person_hbx_id: person.hbx_id,
      application: faa_application
    )
  end

  let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:income_evidence) { FactoryBot.create(:income_evidence, :with_verification_histories, :outstanding, eligibility: aptc_csr_eligibility) }
  let(:aptc_ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: aptc_csr_eligibility) }

  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: qhp_applicant) }
  let(:ivl_ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: ivl_eligibility) }

  let(:operation) { described_class.new }

  describe '#call' do
    context 'with valid parameters' do
      let(:params) do
        {
          family_id: family.id,
          filter: { year: TimeKeeper.date_of_record.year }
        }
      end

      it 'successfully retrieves applications and returns success' do
        result = operation.call(params: params, family_member: family.primary_applicant, evidence: income_evidence)

        expect(result).to be_success
        expect(result.success[:years]).to include(TimeKeeper.date_of_record.year)
        expect(result.success[:selected_year]).to eq(TimeKeeper.date_of_record.year)
        expect(result.success[:applications]).to include(faa_application)
        expect(result.success[:application_evidence_mapping]).to be_a(Hash)
        expect(result.success[:current_and_previous_application_ids]).to include(faa_application.hbx_id)
        expect(result.success[:bs4]).to be true
        expect(result.success[:bs4]).to be true
      end
    end

    context 'with multiple applications across years' do
      let(:params) do
        {
          family_id: family.id,
          filter: {}
        }
      end

      let(:previous_year_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          aasm_state: 'determined',
          submitted_at: 1.year.ago,
          assistance_year: TimeKeeper.date_of_record.year - 1
        )
      end

      let(:previous_year_applicant) do
        FactoryBot.create(
          :financial_assistance_applicant,
          family_member_id: primary_applicant.id,
          person_hbx_id: person.hbx_id,
          application: previous_year_app
        )
      end

      let(:previous_year_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: previous_year_applicant) }
      let(:previous_year_evidence) { FactoryBot.create(:income_evidence, :outstanding, eligibility: previous_year_eligibility) }

      let(:qhp_application) do
        FactoryBot.create(
          :individual_market_application,
          :with_primary,
          family_id: family.id,
          assistance_year: TimeKeeper.date_of_record.year
        )
      end

      let(:qhp_applicant) do
        FactoryBot.create(:individual_market_applicant, application: qhp_application,
                                                        family_member_id: primary_applicant.id)
      end

      before do
        previous_year_app
        previous_year_evidence
        qhp_application
        ivl_eligibility
        ivl_ssn_evidence
      end

      it 'fetches all applications for the family' do
        result = operation.call(params: params, family_member: family.primary_applicant, evidence: income_evidence)

        expect(result).to be_success
        expect(result.success[:applications]).to include(faa_application)
        # Should filter by current year by default
        expect(result.success[:applications]).not_to include(previous_year_app)
      end

      it 'sorts years in descending order' do
        result = operation.call(params: params, family_member: family.primary_applicant, evidence: income_evidence)

        expect(result).to be_success
        expect(result.success[:years]).to eq([TimeKeeper.date_of_record.year, TimeKeeper.date_of_record.year - 1].sort.reverse)
      end
    end

    context 'with year filter applied' do
      let(:previous_year) { TimeKeeper.date_of_record.year - 1 }
      let(:params) do
        {
          family_id: family.id,
          filter: { year: previous_year }
        }
      end

      let(:previous_year_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          aasm_state: 'determined',
          submitted_at: 1.year.ago,
          assistance_year: previous_year
        )
      end

      let(:previous_year_applicant) do
        FactoryBot.create(
          :financial_assistance_applicant,
          family_member_id: primary_applicant.id,
          person_hbx_id: person.hbx_id,
          application: previous_year_app
        )
      end

      let(:previous_year_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: previous_year_applicant) }
      let(:previous_year_evidence) { FactoryBot.create(:income_evidence, :outstanding, eligibility: previous_year_eligibility) }

      before do
        previous_year_app
        previous_year_evidence
      end

      it 'only returns applications for the selected year' do
        result = operation.call(params: params, family_member: family.primary_applicant, evidence: income_evidence)

        expect(result).to be_success
        expect(result.success[:applications]).to include(previous_year_app)
        expect(result.success[:applications]).not_to include(faa_application)
        expect(result.success[:selected_year]).to eq(previous_year)
      end
    end

    context 'with applications sorted by submission date' do
      let(:params) do
        {
          family_id: family.id,
          filter: { year: TimeKeeper.date_of_record.year }
        }
      end

      let(:older_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          aasm_state: 'determined',
          submitted_at: 2.months.ago,
          assistance_year: TimeKeeper.date_of_record.year
        )
      end

      let(:newer_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          aasm_state: 'determined',
          submitted_at: 1.month.ago,
          assistance_year: TimeKeeper.date_of_record.year
        )
      end

      let(:older_applicant) do
        FactoryBot.create(
          :financial_assistance_applicant,
          family_member_id: primary_applicant.id,
          person_hbx_id: person.hbx_id,
          application: older_app
        )
      end

      let(:newer_applicant) do
        FactoryBot.create(
          :financial_assistance_applicant,
          family_member_id: primary_applicant.id,
          person_hbx_id: person.hbx_id,
          application: newer_app
        )
      end

      let(:older_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: older_applicant) }
      let(:newer_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: newer_applicant) }
      let(:older_evidence) { FactoryBot.create(:income_evidence, :outstanding, eligibility: older_eligibility) }
      let(:newer_evidence) { FactoryBot.create(:income_evidence, :outstanding, eligibility: newer_eligibility) }

      before do
        older_app
        newer_app
        older_eligibility
        newer_eligibility
        older_evidence
        newer_evidence
      end

      it 'sorts applications by submission date in descending order' do
        result = operation.call(params: params, family_member: family.primary_applicant, evidence: newer_evidence)

        expect(result).to be_success
        expect(result.success[:applications].first).to eq(newer_app)
        expect(result.success[:applications].last).to eq(older_app)
      end
    end

    context 'with invalid parameters' do
      context 'when evidence is blank' do
        let(:params) do
          {
            family_id: family.id,
            filter: { year: TimeKeeper.date_of_record.year }
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params: params, family_member: family.primary_applicant, evidence: nil)

          expect(result).to be_failure
          expect(result.failure).to eq("Evidence not found")
        end
      end

      context 'when family_id is blank' do
        let(:params) do
          {
            family_id: nil,
            filter: { year: TimeKeeper.date_of_record.year }
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params: params, family_member: family.primary_applicant, evidence: income_evidence)

          expect(result).to be_failure
          expect(result.failure).to eq("Family ID is required")
        end
      end

      context 'when no applications are found' do
        let(:params) do
          {
            family_id: family.id,
            filter: { year: TimeKeeper.date_of_record.year }
          }
        end

        before do
          allow(::IndividualMarket::Application).to receive(:where).and_return(::IndividualMarket::Application.none)
          allow(::FinancialAssistance::Application).to receive(:where).and_return(::FinancialAssistance::Application.none)
        end

        it 'returns failure when no applications exist' do
          result = operation.call(params: params, family_member: family.primary_applicant, evidence: income_evidence)

          expect(result).to be_failure
          expect(result.failure).to eq("No applications found for family")
        end
      end
    end

    context 'when no matching applications found for family' do
      let(:user_2) { FactoryBot.create(:user, person: person_2) }
      let(:person_2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
      let(:family_2) { FactoryBot.create(:family, :with_primary_family_member, person: person_2) }
      let(:params) do
        {
          family_id: family_2.id,
          filter: { year: TimeKeeper.date_of_record.year }
        }
      end

      it 'returns failure' do
        result = operation.call(params: params, family_member: family.primary_applicant, evidence: income_evidence)

        expect(result).to be_failure
        expect(result.failure).to eq("No applications found for family")
      end
    end
  end
end
