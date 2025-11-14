# frozen_string_literal: true

RSpec.describe Operations::Eligibilities::Evidences::Documents::Index, type: :operation do
  let(:user) { FactoryBot.create(:user, person: person) }
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:person_2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_family_member }
  let(:dependent_family_member) do
    FactoryBot.create(:family_member, family: family, person: person_2)
  end

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

  let(:applicant_2) do
    FactoryBot.create(
      :financial_assistance_applicant,
      family_member_id: dependent_family_member.id,
      person_hbx_id: person_2.hbx_id,
      application: faa_application
    )
  end

  let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:income_evidence) { FactoryBot.create(:income_evidence, :with_verification_histories, :outstanding, eligibility: aptc_csr_eligibility) }
  let(:aptc_ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: aptc_csr_eligibility) }

  let(:aptc_csr_eligibility_2) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant_2) }
  let(:income_evidence_2) { FactoryBot.create(:income_evidence, :with_verification_histories, :outstanding, eligibility: aptc_csr_eligibility_2) }
  let(:aptc_ssn_evidence_2) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: aptc_csr_eligibility_2) }


  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: qhp_applicant) }
  let(:ivl_ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: ivl_eligibility) }

  let(:operation) { described_class.new }

  describe '#call' do
    context 'with valid parameters' do
      let(:params) do
        {
          family_id: family.id,
          year: TimeKeeper.date_of_record.year,
          page: 1,
          per_page: 10
        }
      end

      before do
        income_evidence.documents.create!(identifier: "test-1#sample-key",
                                          title: "sample-document.pdf", subject: "sample-document.pdf", created_at: Date.today)
        income_evidence_2.documents.create!(identifier: "test-2#sample-key",
                                          title: "sample-document.pdf", subject: "sample-document.pdf")
      end

      it 'successfully retrieves documents only related to primary applicant and returns success' do
        result = operation.call(params: params, evidence: income_evidence)

        expect(result).to be_success
        expect(result.success[:years]).to include(TimeKeeper.date_of_record.year)
        expect(result.success[:selected_year]).to eq(TimeKeeper.date_of_record.year)
        expect(result.success[:page]).to eq(1)
        expect(result.success[:per_page]).to eq(10)
        expect(result.success[:applications]).to include(faa_application)
        expect(result.success[:all_documents].count).to eq(1)
        expect(result.success[:all_documents].first.identifier).to eq("test-1#sample-key")
      end

      it 'successfully retrieves documents only related to dependent applicant and returns success' do
        result = operation.call(params: params, evidence: income_evidence_2)

        expect(result).to be_success
        expect(result.success[:years]).to include(TimeKeeper.date_of_record.year)
        expect(result.success[:selected_year]).to eq(TimeKeeper.date_of_record.year)
        expect(result.success[:page]).to eq(1)
        expect(result.success[:per_page]).to eq(10)
        expect(result.success[:applications]).to include(faa_application)
        expect(result.success[:all_documents].count).to eq(1)
        expect(result.success[:all_documents].first.identifier).to eq("test-2#sample-key")
      end

      context "#fetch_documents_with_app_ids" do

        context "evidence with documents" do
          before do
            income_evidence.documents.create!(identifier: "test-1#sample-key", title: "sample-document.pdf", subject: "sample-document.pdf")
          end

          let(:all_documents) { [income_evidence.documents.first] }

          it "successfully sorts documents based on created at date" do
            result = operation.send(:fetch_documents_with_app_ids, [faa_application], income_evidence)
            expect(result.value![:documents]).to eq(income_evidence.documents.to_a.reverse)
          end
        end

        context "evidence without documents" do
          before do
            income_evidence.documents.destroy_all
          end

          it "returns no documents" do
            result = operation.send(:fetch_documents_with_app_ids, [faa_application], income_evidence)
            expect(result.value![:documents]).to be_empty
          end
        end
      end
    end

    context 'with multiple applications across years' do
      let(:params) do
        {
          family_id: family.id,
          page: 1,
          per_page: 10
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
        qhp_application
        income_evidence.documents.create!(identifier: "test#sample-key",
                                          title: "sample-document.pdf", subject: "sample-document.pdf")
        ivl_ssn_evidence.documents.create!(identifier: "test#sample-key",
                                           title: "sample-document.pdf", subject: "sample-document.pdf")
      end

      it 'fetches all applications for the family' do
        result = operation.call(params: params, evidence: income_evidence)

        expect(result).to be_success
        expect(result.success[:applications]).to include(faa_application)
        expect(result.success[:applications]).to include(qhp_application)
      end

      it 'sorts years in descending order for income_evidence' do
        result = operation.call(params: params, evidence: income_evidence)

        expect(result).to be_success
        expect(result.success[:years]).to eq([TimeKeeper.date_of_record.year, TimeKeeper.date_of_record.year - 1].sort.reverse)
      end

      it 'sorts years in descending order for ivl_ssn_evidence' do
        result = operation.call(params: params, evidence: ivl_ssn_evidence)

        expect(result).to be_success
        expect(result.success[:years]).to eq([TimeKeeper.date_of_record.year, TimeKeeper.date_of_record.year - 1].sort.reverse)
        expect(result.success[:uploads]).to be_present
      end
    end

    context 'with year filter applied' do
      let(:previous_year) { TimeKeeper.date_of_record.year - 1 }
      let(:params) do
        {
          family_id: family.id,
          year: previous_year,
          page: 1,
          per_page: 10
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

      before do
        previous_year_app
        income_evidence.documents.create!(identifier: "test#sample-key",
                                          title: "sample-document.pdf", subject: "sample-document.pdf")
      end

      it 'only returns applications for the selected year' do
        result = operation.call(params: params, evidence: income_evidence)

        expect(result).to be_success
        expect(result.success[:applications]).to include(previous_year_app)
        expect(result.success[:applications]).not_to include(faa_application)
        expect(result.success[:selected_year]).to eq(previous_year)
      end
    end

    context 'with pagination' do
      let(:params) do
        {
          family_id: family.id,
          page: 2,
          per_page: 5
        }
      end

      before do
        12.times do
          income_evidence.documents.create!(identifier: "test#sample-key",
                                            title: "sample-document.pdf", subject: "sample-document.pdf")
        end
      end

      it 'paginates the results correctly' do
        result = operation.call(params: params, evidence: income_evidence)

        expect(result).to be_success
        expect(result.success[:page]).to eq(2)
        expect(result.success[:per_page]).to eq(5)
        expect(result.success[:uploads].size).to be <= 5
        expect(result.success[:total_pages]).to eq(3)
      end
    end

    context 'with invalid parameters' do
      context 'when evidence is blank' do
        let(:params) do
          {
            family_id: family.id,
            page: 1,
            per_page: 10
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params: params, evidence: nil)

          expect(result).to be_failure
          expect(result.failure).to eq("Evidence not found")
        end
      end

      context 'when family_id is blank' do
        let(:params) do
          {
            family_id: nil,
            page: 1,
            per_page: 10
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params: params, evidence: income_evidence)

          expect(result).to be_failure
          expect(result.failure).to eq("Family ID is required")
        end
      end

      context 'when no applications are found' do
        let(:params) do
          {
            family_id: family.id,
            page: 1,
            per_page: 10
          }
        end

        before do
          allow(::IndividualMarket::Application).to receive(:where).and_return(::IndividualMarket::Application.none)
          allow(::FinancialAssistance::Application).to receive(:where).and_return(::FinancialAssistance::Application.none)
        end

        it 'returns failure when no applications exist' do
          result = operation.call(params: params, evidence: income_evidence)

          expect(result).to be_failure
          expect(result.failure).to eq("No applications found for family")
        end
      end
    end

    context 'when there are no documents' do
      let(:params) do
        {
          family_id: family.id,
          page: 1,
          per_page: 10
        }
      end

      it 'returns empty uploads array' do
        result = operation.call(params: params, evidence: income_evidence)

        expect(result).to be_success
        expect(result.success[:uploads]).to be_empty
        expect(result.success[:total_pages]).to eq(0)
      end
    end
  end
end
