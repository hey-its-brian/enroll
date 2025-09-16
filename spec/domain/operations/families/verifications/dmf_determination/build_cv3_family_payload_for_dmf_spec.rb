# frozen_string_literal: true

require 'rails_helper'
require 'shared_contexts/dual_applications_with_eligible_family_setup'

RSpec.describe Operations::Families::Verifications::DmfDetermination::BuildCv3FamilyPayloadForDmf, dbclean: :after_each do
  include Dry::Monads[:result, :do]

  let(:primary_dob){ Date.today - 57.years }
  let(:primary) { FactoryBot.create(:person, :with_consumer_role, dob: primary_dob, ssn: 101_011_011) }
  let(:family) do
    FactoryBot.create(:family, :with_primary_family_member, person: primary)
  end

  let(:spouse_person) { FactoryBot.create(:person, :with_consumer_role, dob: spouse_dob, ssn: 101_011_012) }
  let!(:spouse) { FactoryBot.create(:family_member, person: spouse_person, family: family) }
  let(:spouse_dob) { Date.today - 55.years }

  let(:product) do
    FactoryBot.create(:benefit_markets_products_health_products_health_product,
                      :with_issuer_profile,
                      metal_level_kind: :silver,
                      benefit_market_kind: :aca_individual)
  end
  let!(:enrollment) do
    FactoryBot.create(:hbx_enrollment,
                      :with_enrollment_members,
                      family: family,
                      enrollment_members: enrolled_members,
                      household: family.active_household,
                      coverage_kind: :health,
                      effective_on: Date.today,
                      kind: "individual",
                      product: product,
                      rating_area_id: primary.consumer_role.rating_address.id,
                      consumer_role_id: family.primary_person.consumer_role.id,
                      aasm_state: 'coverage_selected')
  end

  let(:date) { DateTime.now }

  let(:job) do
    ::Operations::Transmittable::CreateJob.new.call(
      {
        key: :dmf_determination,
        title: 'Bulk DMF Determination call',
        description: "Job that requests begin coverage of all renewal IVL enrollments.",
        publish_on: date,
        started_at: date
      }
    ).success
  end

  let(:title) { "#{job.title} Request" }
  let(:description) { "#{job&.description}: individual call for family with hbx_id #{family.hbx_assigned_id}" }

  let(:transmission) do
    ::Operations::Transmittable::CreateTransmission.new.call(
      {
        job: job,
        key: :dmf_determination_request,
        title: title,
        description: description,
        correlation_id: family.hbx_assigned_id.to_s,
        publish_on: date,
        started_at: date,
        event: 'initial',
        state_key: :initial
      }
    ).success
  end

  let(:transaction) do
    ::Operations::Transmittable::CreateTransaction.new.call(
      {
        transmission: transmission,
        subject: family,
        key: :dmf_determination_request,
        title: title,
        description: description,
        correlation_id: family.hbx_assigned_id.to_s,
        publish_on: date,
        started_at: date,
        event: 'initial',
        state_key: :initial
      }
    ).success
  end

  let(:transmittable_params) {{ job: job, transmission: transmission, transaction: transaction }}
  let(:dependent) { family.dependents.last.person }

  before do
    allow(EnrollRegistry[:alive_status].feature).to receive(:is_enabled).and_return(true)
    primary.build_demographics_group
    spouse_person.build_demographics_group
  end

  context "with no determined applications" do
    before do
      allow(family).to receive(:all_family_member_relations_defined).and_return(true)
      BenefitMarkets::Products::ProductRateCache.initialize_rate_cache!

      Operations::Eligibilities::BuildFamilyDetermination.new.call({ effective_date: Date.today, family: family })
    end

    context "success" do
      context 'with all valid members with an enrollment' do
        let(:spouse_person) { FactoryBot.create(:person, :with_consumer_role, dob: spouse_dob, ssn: 101_011_012) }
        let(:enrolled_members) { family.family_members }

        it "should pass" do
          result = described_class.new.call(family, transmittable_params)
          expect(result).to be_success
        end
      end

      context 'with some non-enrolled members' do
        let(:spouse_person) { FactoryBot.create(:person, :with_consumer_role, dob: spouse_dob, ssn: 101_011_012) }
        let(:enrolled_members) { [family.family_members.first] }

        before do
          @result = described_class.new.call(family, transmittable_params)
        end

        it "should pass" do
          expect(@result).to be_success
        end

        it "should add type verification element to ineligible member verification" do
          dependent.reload
          element = dependent.alive_status.type_history_elements.last

          expect(element.action).to eq 'dmf_request_failed'
          expect(element.update_reason).to eq "Family Member is not eligible for DMF Determination due to errors: [\"No states found for the given subject/member hbx_id: #{dependent.hbx_id} \"]"
        end
      end

      context 'with some members with invalid ssns' do
        let(:spouse_person) { FactoryBot.create(:person, :with_consumer_role, dob: spouse_dob, ssn: nil) }
        let(:enrolled_members) { family.family_members }

        before do
          @result = described_class.new.call(family, transmittable_params)
        end

        it "should pass" do
          expect(@result).to be_success
        end

        it "should add type verification element to ineligible member verification" do
          dependent.reload
          element = dependent.alive_status.type_history_elements.last

          expect(element.action).to eq 'dmf_request_failed'
          expect(element.update_reason).to eq "Family Member is not eligible for DMF Determination due to errors: [\"No SSN for member #{dependent.hbx_id}\"]"
        end
      end

      context 'parsing cv3_family after being published' do
        let(:enrolled_members) { family.family_members }

        it "should be able to be parsed from JSON and validate with AcaEntities::Operations::CreateFamily" do
          described_class.new.call(family, transmittable_params)
          transaction.reload
          # we will convert this to json and then parse with JSON to simulate FDSH handling the event
          payload = transaction.json_payload[:family_hash]
          json_payload = payload.to_json
          parsed_payload = JSON.parse(json_payload, symbolize_names: true)
          valid_payload = AcaEntities::Operations::CreateFamily.new.call(parsed_payload)

          expect(valid_payload).to be_success
        end
      end
    end

    context "failure" do
      let(:enrolled_members) { [family.family_members.first] }
      let(:fake_cv3_transformer) { double(Operations::Transformers::FamilyTo::Cv3Family) }

      context 'cv3 transformation failure' do
        before do
          allow(Operations::Transformers::FamilyTo::Cv3Family).to receive(:new).and_return(fake_cv3_transformer)
          allow(fake_cv3_transformer).to receive(:call).and_return(Failure('Unable to transform family into cv3_family'))

          @result = described_class.new.call(family, transmittable_params)
        end

        it 'should fail' do
          # no members have their subject changed to is_eligibile: true
          expect(@result).to be_failure
        end

        it 'should add a history element to all alive_status verifications' do
          alive_status_elements = [primary.alive_status, dependent.alive_status].map(&:type_history_elements)

          expect(alive_status_elements.all? { |elements| elements.last.update_reason.include?('Unable to transform family into cv3_family') }).to be_truthy
        end

        it "should update the transmission" do
          transmission.reload
          expect(transmission.process_status.latest_state).to eq :failed
          expect(transmission.transmittable_errors.size).to eq 1
          expect(transmission.transmittable_errors.last.message).to include('Unable to transform family into cv3_family')
        end

        it "should update the transaction" do
          transaction.reload
          expect(transaction.process_status.latest_state).to eq :failed
          expect(transaction.transmittable_errors.size).to eq 1
          expect(transaction.transmittable_errors.last.message).to include('Unable to transform family into cv3_family')
        end
      end

      context 'aca_entities validation failure' do
        before do
          allow(Operations::Transformers::FamilyTo::Cv3Family).to receive(:new).and_return(fake_cv3_transformer)
          allow(fake_cv3_transformer).to receive(:call).and_return(Success('success'))

          @result = described_class.new.call(family, transmittable_params)
        end

        it 'should fail' do
          # no members have their subject changed to is_eligibile: true
          expect(@result).to be_failure
        end

        it 'should add a history element to all alive_status verifications' do
          alive_status_elements = [primary.alive_status, dependent.alive_status].map(&:type_history_elements)

          expect(alive_status_elements.all? { |elements| elements.last.update_reason.include?('Invalid cv3 family') }).to be_truthy
        end

        it "should update the transmission" do
          transmission.reload
          expect(transmission.process_status.latest_state).to eq :failed
          expect(transmission.transmittable_errors.size).to eq 1
          expect(transmission.transmittable_errors.last.message).to include('Invalid cv3 family')
        end

        it "should update the transaction" do
          transaction.reload
          expect(transaction.process_status.latest_state).to eq :failed
          expect(transaction.transmittable_errors.size).to eq 1
          expect(transaction.transmittable_errors.last.message).to include('Invalid cv3 family')
        end
      end

      context 'with all members ineligible' do
        let(:enrolled_members) { [] }

        before do
          @result = described_class.new.call(family, transmittable_params)
        end

        it 'should fail' do
          expect(@result).to be_failure
        end

        it 'should add a history element to all alive_status verifications' do
          alive_status_elements = [primary.alive_status, dependent.alive_status].map(&:type_history_elements)

          expect(alive_status_elements.all? { |elements| elements.last.update_reason.match?("No states found for the given subject/member hbx_id") }).to be_truthy
        end

        it "should update the transmission" do
          transmission.reload
          expect(transmission.process_status.latest_state).to eq :failed
          expect(transmission.transmittable_errors.size).to eq 1
          expect(transmission.transmittable_errors.last.message).to include('DMF Determination not sent: no family members are eligible')
        end

        it "should update the transaction" do
          transaction.reload
          expect(transaction.process_status.latest_state).to eq :failed
          expect(transaction.transmittable_errors.size).to eq 1
          expect(transaction.transmittable_errors.last.message).to include('DMF Determination not sent: no family members are eligible')
        end
      end
    end
  end

  context 'with qhp_application feature enabled' do
    include_context 'dual applications with eligible family setup'

    shared_examples 'validating cv3 family with active application' do |_app_type|
      context 'with all members with a valid enrollment' do
        let(:enrolled_members) { family.family_members }

        it "should pass" do
          result = described_class.new.call(family, transmittable_params, application: current_application)
          expect(result).to be_success
        end

        context 'with active tax_household_groups' do
          before do
            year = Date.today.year
            thhg = family.tax_household_groups.create!(
              assistance_year: year,
              source: 'qhp',
              start_on: Date.new(year),
              tax_households: [FactoryBot.build(:tax_household, household: family.active_household)]
            )
            thhg.tax_households.first.tax_household_members.create!(
              applicant_id: family.primary_applicant.id, is_ia_eligible: true
            )
            family.reload
          end

          it "should pass" do
            result = described_class.new.call(family, transmittable_params, application: current_application)
            expect(result).to be_success
          end
        end
      end

      context 'with some members with a valid enrollment' do
        let(:enrolled_members) { [family.family_members.first] }

        it 'should pass' do
          result = described_class.new.call(family, transmittable_params, application: current_application)
          expect(result).to be_success
        end

        it 'should create a verification history for any non-eligible applicants' do
          described_class.new.call(family, transmittable_params, application: current_application)
          current_application.reload
          non_eligible_applicant = (if current_application.is_a?(FinancialAssistance::Application)
                                      current_application.dependents
                                    else
                                      current_application.non_primary_applicants
                                    end).first

          evidence = non_eligible_applicant.individual_market_eligibility.alive_evidence

          expect(evidence.verification_histories.size).to eq 1
          expect(evidence.verification_histories.first.action).to eq 'dmf_request_failed'
        end
      end

      context 'with no members with a valid enrollment' do
        let(:enrolled_members) { [] }

        it 'should fail' do
          result = described_class.new.call(family, transmittable_params, application: current_application)
          expect(result).to be_failure
        end

        it 'should create a verification history for all applicants' do
          described_class.new.call(family, transmittable_params, application: current_application)
          current_application.reload

          applicant1 = current_application.primary_applicant
          applicant2 = (if current_application.is_a?(FinancialAssistance::Application)
                          current_application.dependents
                        else
                          current_application.non_primary_applicants
                        end).first
          evidence1 = applicant1.individual_market_eligibility.alive_evidence
          evidence2 = applicant2.individual_market_eligibility.alive_evidence

          [evidence1, evidence2].each do |evidence|
            expect(evidence.verification_histories.size).to eq 1
            expect(evidence.verification_histories.first.action).to eq 'dmf_request_failed'
          end
        end
      end
    end

    context 'with a financial assistance application' do
      let!(:current_application) { create_financial_assistance_application }

      include_examples 'validating cv3 family with active application', 'faa'
    end

    context 'with an individual market application' do
      let!(:current_application) { create_individual_market_application }

      include_examples 'validating cv3 family with active application', 'qhp'
    end
  end
end
