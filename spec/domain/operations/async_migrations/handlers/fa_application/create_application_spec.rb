# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Handlers::FAApplication::CreateApplication, dbclean: :after_each do
  include Dry::Monads[:do, :result]

  before :all do
    DatabaseCleaner.clean
  end

  let!(:hbx_profile) { FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period) }
  let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
  let(:benefit_coverage_period) { hbx_profile.benefit_sponsorship.benefit_coverage_periods.first }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, age_off_excluded: true, first_name: "main_name") }
  let(:consumer_role) do
    consumer = person.consumer_role
    consumer.contact_method = "Paper and Electronic communications"
    consumer.language_preference = "test"
    consumer.save!
    consumer
  end

  let!(:immigration_type) do
    immigration_type = FactoryBot.build(:verification_type, type_name: 'Immigration status',
                                                            validation_status: 'rejected',
                                                            applied_roles: ['consumer_role'],
                                                            update_reason: 'initial',
                                                            rejected: false,
                                                            external_service: 'some_service',
                                                            due_date: Date.today,
                                                            due_date_type: 'admin',
                                                            updated_by: 'admin',
                                                            inactive: true)
    person.verification_types << immigration_type
    person.save!
  end

  let(:response_payload) do
    {
      :SSACompositeIndividualResponses => [
        {
          :ResponseMetadata => {
            :ResponseCode => "HS000000",
            :ResponseDescriptionText => "ResponseDescriptionText0",
            :TDSResponseDescriptionText => "TDSResponseDescriptionText0"
          },
          :PersonSSNIdentification => "100101000",
          :SSAResponse => {
            :SSNVerificationIndicator => true,
            :DeathConfirmationCode => "Confirmed",
            :PersonUSCitizenIndicator => true,
            :PersonIncarcerationInformationIndicator => false
          }
        }
      ],
      :ResponseMetadata => {
        :ResponseCode => "HS000000",
        :ResponseDescriptionText => "ResponseDescriptionText0",
        :TDSResponseDescriptionText => "TDSResponseDescriptionText0"
      }
    }
  end
  let(:response1) do
    consumer_role.lawful_presence_determination.ssa_responses << EventResponse.new({received_at: Time.now, body: response_payload.to_json})
    consumer_role.lawful_presence_determination.ssa_responses.last.save!
    consumer_role.lawful_presence_determination.ssa_responses.last
  end

  let(:response2) do
    consumer_role.lawful_presence_determination.vlp_responses << EventResponse.new({received_at: Time.now, body: response_payload.to_json})
    consumer_role.lawful_presence_determination.vlp_responses.last.save!
    consumer_role.lawful_presence_determination.vlp_responses.last
  end

  let(:response3) do
    consumer_role.alive_status_responses << EventResponse.new({received_at: Time.now, body: response_payload.to_json})
    consumer_role.alive_status_responses.last.save!
    consumer_role.alive_status_responses.last
  end

  let!(:update_type_history_elements) do
    person.verification_types.ssn_type.each do |verification_type|
      verification_type.assign_attributes(validation_status: "review",
                                          applied_roles: ["consumer_role"],
                                          update_reason: "upload",
                                          rejected: false,
                                          external_service: "some_service",
                                          due_date: Date.today,
                                          due_date_type: "admin",
                                          updated_by: "user",
                                          inactive: false)
      verification_type.add_type_history_element(action: "upload",
                                                 modifier: "user",
                                                 update_reason: "document uploaded",
                                                 event_response_record_id: nil,
                                                 created_at: DateTime.now - 30.days)

      verification_type.add_type_history_element(action: "FDSH SSA Hub Response",
                                                 modifier: "external Hub",
                                                 update_reason: "Hub response",
                                                 event_response_record_id: response1.id,
                                                 created_at: DateTime.now - 40.days)

      verification_type.add_type_history_element(action: "call hub",
                                                 modifier: "admin",
                                                 update_reason: "Hub request",
                                                 event_response_record_id: nil,
                                                 created_at: DateTime.now - 40.days)
      verification_type.save!

    end

    person.verification_types.citizenship_type.each do |verification_type|
      verification_type.assign_attributes(validation_status: "verified",
                                          applied_roles: ["consumer_role"],
                                          update_reason: "response received",
                                          rejected: false,
                                          external_service: "some_service",
                                          due_date: Date.today,
                                          due_date_type: "admin",
                                          updated_by: "admin",
                                          inactive: false)

      verification_type.add_type_history_element(action: "FDSH citizen Hub Response",
                                                 modifier: "external Hub for citizenship",
                                                 update_reason: "Hub response",
                                                 event_response_record_id: response2.id,
                                                 created_at: DateTime.now)

      verification_type.add_type_history_element(action: "call hub",
                                                 modifier: "admin",
                                                 update_reason: "Hub request for citizenship",
                                                 event_response_record_id: nil,
                                                 created_at: DateTime.now - 10.minutes)

      verification_type.vlp_documents << VlpDocument.new(title: 'document.pdf', creator: 'mehl', subject: 'document.pdf', publisher: 'mehl', type: 'text', identifier: 'identifier', source: 'enroll_system',
                                                         language: 'en')
      verification_type.vlp_documents << VlpDocument.new(title: 'document2.pdf', creator: 'mehl2', subject: 'document2.pdf', publisher: 'mehl', type: 'text', source: 'enroll_system',
                                                         language: 'en')
      verification_type.save!

    end

    person.verification_types.by_name("Immigration status").each do |verification_type|

      verification_type.add_type_history_element(action: "reject",
                                                 modifier: "admin",
                                                 update_reason: "no documents",
                                                 created_at: DateTime.now)

      verification_type.add_type_history_element(action: "FDSH Immigration Hub Response",
                                                 modifier: "external Hub for Immigration",
                                                 update_reason: "Hub response",
                                                 event_response_record_id: response2.id,
                                                 created_at: DateTime.now - 9.minutes)

      verification_type.add_type_history_element(action: "call hub",
                                                 modifier: "admin",
                                                 update_reason: "Hub request for Immigration",
                                                 event_response_record_id: nil,
                                                 created_at: DateTime.now - 10.minutes)

      verification_type.vlp_documents << VlpDocument.new(title: 'document.pdf', creator: 'mehl', subject: 'document.pdf', publisher: 'mehl', type: 'text', identifier: 'identifier', source: 'enroll_system',
                                                         language: 'en')
      verification_type.vlp_documents << VlpDocument.new(title: 'document3.pdf', creator: 'mehl3', subject: 'document3.pdf', publisher: 'mehl', type: 'text3', identifier: 'identifier3', source: 'enroll_system3',
                                                         language: 'en3')
      verification_type.save!
    end
  end

  let!(:draft_application) do
    FactoryBot.create(:application,
                      family_id: family.id,
                      aasm_state: "draft",
                      effective_date: (TimeKeeper.date_of_record - 12.days),
                      origin: :user,
                      assistance_year: nil,
                      generation_reason: :manual)
  end

  let!(:draft_applicant) do
    FactoryBot.create(:applicant,
                      application: draft_application,
                      dob: TimeKeeper.date_of_record - 40.years,
                      is_primary_applicant: true,
                      family_member_id: family.family_members[0].id,
                      person_hbx_id: person.hbx_id,
                      addresses: [FactoryBot.build(:financial_assistance_address)])
  end

  let!(:application) do
    FactoryBot.create(:application,
                      family_id: family.id,
                      aasm_state: "determined",
                      effective_date: (TimeKeeper.date_of_record - 12.days),
                      origin: :user,
                      assistance_year: TimeKeeper.date_of_record.year,
                      generation_reason: :manual,
                      has_eligibility_response: true,
                      transfer_requested: true,
                      account_transferred: true,
                      has_mec_check_response: true,
                      applicant_kind: "user and/or family",
                      request_kind: "placeholder",
                      motivation_kind: "insurance_affordability",
                      us_state: "ME",
                      is_ridp_verified: true,
                      renewal_base_year: TimeKeeper.date_of_record.year + 1)
  end

  let!(:eligibility_determination1) { FactoryBot.create(:financial_assistance_eligibility_determination, application: application) }

  let(:override_rules) {::AcaEntities::MagiMedicaid::Types::EligibilityOverrideRule.values}
  let(:member_determinations) do
    [medicaid_and_chip_member_determination, medicaid_and_chip_member_determination]
  end

  let(:medicaid_and_chip_member_determination) do
    {
      kind: 'Medicaid/CHIP Determination',
      criteria_met: false,
      determination_reasons: ["test"],
      eligibility_overrides: medicaid_chip_eligibility_overrides
    }
  end

  let(:medicaid_chip_eligibility_overrides) do
    override_rules.map do |rule|
      {
        override_rule: rule,
        override_applied: false
      }
    end
  end

  let!(:applicant) do
    FactoryBot.create(:applicant,
                      first_name: "app_nmae",
                      application: application,
                      dob: TimeKeeper.date_of_record - 40.years,
                      is_primary_applicant: true,
                      family_member_id: family.family_members[0].id,
                      person_hbx_id: person.hbx_id,
                      addresses: [FactoryBot.build(:financial_assistance_address)],
                      eligibility_determination_id: eligibility_determination1.id,
                      is_eligible_for_non_magi_reasons: true,
                      magi_medicaid_category: "medicaid",
                      medicaid_household_size: 3,
                      magi_medicaid_monthly_household_income: 1000,
                      magi_medicaid_monthly_income_limit: 2000,
                      magi_as_percentage_of_fpl: 150,
                      csr_percent_as_integer: 87,
                      csr_eligibility_kind: "csr_87",
                      benchmark_premiums: {"health_only_slcsp_premiums" => [{"member_identifier" => "1281306", "monthly_premium" => 1060.57}],
                                           "health_only_lcsp_premiums" => [{"member_identifier" => "1281306", "monthly_premium" => 1058.99}]},
                      contact_method: "Paper and Electronic communications",
                      language_preference: "test",
                      is_ia_eligible: true,
                      is_csr_eligible: true,
                      is_medicaid_chip_eligible: true,
                      is_non_magi_medicaid_eligible: true,
                      is_totally_ineligible: true,
                      is_without_assistance: true,
                      is_magi_medicaid: true,
                      is_gap_filling: true,
                      member_determinations: member_determinations)
  end

  describe 'migrate evidences' do
    before do
      allow(EnrollRegistry[:alive_status].feature).to receive(:is_enabled).and_return(true)
    end

    let!(:aptc_csr_eligibility)  do
      eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: applicant)
      old_state = FactoryBot.build(:v3_state_history, created_at: 2.days.ago)
      new_state = FactoryBot.build(:v3_state_history, created_at: 1.day.ago)
      eligibility.state_histories << old_state
      eligibility.state_histories << new_state
      eligibility.save!
      eligibility
    end

    let(:evidence) do
      FactoryBot.create(:income_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::IncomeEvidence',key: :income_evidence, title: 'Income Evidence', determined_at: TimeKeeper.date_of_record,
                                          description: 'Income Evidence Description', current_state: :pending)
    end
    let!(:old_state_history) { FactoryBot.create(:v3_state_history, status_trackable: evidence, created_at: 2.days.ago) }
    let!(:new_state_history) { FactoryBot.create(:v3_state_history, status_trackable: evidence, created_at: 1.day.ago) }
    let!(:v3_verification_history)  { FactoryBot.create(:v3_verification_history, evidence: evidence) }
    let!(:v3_request_result)  { FactoryBot.create(:v3_request_result, evidence: evidence) }

    let!(:document) do
      evidence.documents.create(title: 'document.pdf', creator: 'mehl', subject: 'document.pdf', publisher: 'mehl', type: 'text', identifier: 'identifier', source: 'enroll_system', language: 'en')
    end

    context '#perform' do
      before do
        allow(EnrollRegistry[:alive_status].feature).to receive(:is_enabled).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
        consumer_role.save!
        person.verification_types.where(type_name: "DC Residency").delete_all
        person.verification_types.alive_status_type.each do |verification_type|
          verification_type.add_type_history_element(action: "FDSH alive status Hub Response",
                                                     modifier: "external Hub",
                                                     update_reason: "Hub response",
                                                     event_response_record_id: response3.id,
                                                     to_validation_status: "verified",
                                                     from_validation_status: "unverified",
                                                     created_at: DateTime.now)

          verification_type.add_type_history_element(action: "call hub",
                                                     modifier: "admin",
                                                     update_reason: "Hub request",
                                                     event_response_record_id: nil,
                                                     created_at: DateTime.now - 5.minutes)
          verification_type.save!
        end
      end

      context 'when the application is created' do
        before do
          allow(application.family).to receive(:application_applicable_year).and_return(TimeKeeper.date_of_record.year)
          @result = subject.call({document_id: application.id.to_s})
          @old_applicant = application.applicants.first
          @new_application_hbx_id = @result.value![1]
          @new_application = FinancialAssistance::Application.where(hbx_id: @new_application_hbx_id).first
          @new_application.reload
          @new_applicant = @new_application.applicants.first
          @individual_market_eligibility = @new_applicant.individual_market_eligibility
        end

        it 'should be a success' do
          expect(@result).to be_success
          expect(@new_application.origin).to eq(:migration)
          expect(@new_application.generation_reason).to eq(:manual)
          expect(@new_application.submitted_at).to be_present
          expect(@new_application.eligibility_determinations.count).to eq(1)
          expect(@new_application.eligibility_determinations.first.id).not_to eq(eligibility_determination1.id)
          draft_application.reload
          expect(draft_application.aasm_state).to eq("cancelled")
        end

        it 'should migrate contact method, language preference and age off excluded and others' do
          expect(@new_applicant.age_off_excluded).to eq(person.age_off_excluded)
          expect(@new_applicant.contact_method).to eq(consumer_role.contact_method)
          expect(@new_applicant.language_preference).to eq(consumer_role.language_preference)
          expect(@new_applicant.eligibility_determination_id).not_to eq(@old_applicant.eligibility_determination_id)
          expect(@new_applicant.is_eligible_for_non_magi_reasons).to eq(@old_applicant.is_eligible_for_non_magi_reasons)
          expect(@new_applicant.magi_medicaid_category).to eq(@old_applicant.magi_medicaid_category)
          expect(@new_applicant.medicaid_household_size).to eq(@old_applicant.medicaid_household_size)
          expect(@new_applicant.magi_medicaid_monthly_household_income).to eq(@old_applicant.magi_medicaid_monthly_household_income)
          expect(@new_applicant.magi_medicaid_monthly_income_limit).to eq(@old_applicant.magi_medicaid_monthly_income_limit)
          expect(@new_applicant.magi_as_percentage_of_fpl).to eq(@old_applicant.magi_as_percentage_of_fpl)
          expect(@new_applicant.csr_percent_as_integer).to eq(@old_applicant.csr_percent_as_integer)
          expect(@new_applicant.csr_eligibility_kind).to eq(@old_applicant.csr_eligibility_kind)
          expect(@new_applicant.benchmark_premiums).to eq(@old_applicant.benchmark_premiums)
          expect(@new_applicant.contact_method).to eq(consumer_role.contact_method)
          expect(@new_applicant.language_preference).to eq(consumer_role.language_preference)
          expect(@new_applicant.is_ia_eligible).to eq(@old_applicant.is_ia_eligible)
          expect(@new_applicant.is_csr_eligible).to eq(@old_applicant.is_csr_eligible)
          expect(@new_applicant.is_medicaid_chip_eligible).to eq(@old_applicant.is_medicaid_chip_eligible)
          expect(@new_applicant.is_non_magi_medicaid_eligible).to eq(@old_applicant.is_non_magi_medicaid_eligible)
          expect(@new_applicant.is_totally_ineligible).to eq(@old_applicant.is_totally_ineligible)
          expect(@new_applicant.is_without_assistance).to eq(@old_applicant.is_without_assistance)
          expect(@new_applicant.is_magi_medicaid).to eq(@old_applicant.is_magi_medicaid)
        end

        it 'should migrate applicant member determinations' do
          expect(@new_applicant.member_determinations.count).to eq(@old_applicant.member_determinations.count)
          @new_applicant.member_determinations.each_with_index do |new_member_determination, index|
            old_member_determination = @old_applicant.member_determinations[index]
            expect(new_member_determination.kind).to eq(old_member_determination.kind)
            expect(new_member_determination.criteria_met).to eq(old_member_determination.criteria_met)
            expect(new_member_determination.determination_reasons).to eq(old_member_determination.determination_reasons)
            expect(new_member_determination.eligibility_overrides.map(&:override_rule)).to eq(old_member_determination.eligibility_overrides.map(&:override_rule))
          end
        end

        it 'should migrate other fields' do
          expect(@new_application.has_eligibility_response).to eq(application.has_eligibility_response)
          expect(@new_application.transfer_requested).to eq(application.transfer_requested)
          expect(@new_application.account_transferred).to eq(application.account_transferred)
          expect(@new_application.has_mec_check_response).to eq(application.has_mec_check_response)
          expect(@new_application.applicant_kind).to eq(application.applicant_kind)
          expect(@new_application.request_kind).to eq(application.request_kind)
          expect(@new_application.motivation_kind).to eq(application.motivation_kind)
          expect(@new_application.us_state).to eq(application.us_state)
          expect(@new_application.is_ridp_verified).to eq(application.is_ridp_verified)
          expect(@new_application.effective_date).to eq(application.effective_date)
          expect(@new_application.renewal_base_year).to eq(application.renewal_base_year)
          expect(@new_application.predecessor_id).to eq(application.id)
          expect(@new_application.integrated_case_id).to eq(@new_application.hbx_id)
        end

        it 'should not create application again when triggered the script again' do
          second_result = subject.call({document_id: application.id.to_s})
          expect(second_result).to be_failure
          expect(second_result.failure).to eq("Application hbx id: #{application.hbx_id} with family id: #{application.family_id} is not eligible for migration")
        end
      end

      context 'should migrate individual_market_eligibility' do
        before do
          @result = subject.call({document_id: application.id.to_s})
          @old_applicant = application.applicants.first
          @new_application_hbx_id = @result.value![1]
          @new_application = FinancialAssistance::Application.where(hbx_id: @new_application_hbx_id).first
          @new_application.reload
          @new_applicant = @new_application.applicants.first
          @individual_market_eligibility = @new_applicant.individual_market_eligibility
          @ssn_verification_type = person.verification_types.ssn_type.first
          @type_history_elements = @ssn_verification_type.type_history_elements
          @social_security_number_evidence = @individual_market_eligibility.evidences.select { |e| e.key == "social_security_number_evidence" }.first
          @verification_histories = @social_security_number_evidence.verification_histories
          @request_results = @social_security_number_evidence.request_results
          @state_histories = @social_security_number_evidence.state_histories
        end

        it 'should create individual_market_eligibility' do
          expect(@individual_market_eligibility).to be_present
          expect(@individual_market_eligibility.evidences.count).to eq(person.verification_types.count)
          expect(@individual_market_eligibility.evidences.select(&:is_active).count).to eq(person.verification_types.active.count)
          expect(@individual_market_eligibility.created_at).to be_present
          expect(@individual_market_eligibility.updated_at).to be_present
          expect(@individual_market_eligibility.current_state).to eq(:verification_in_progress)
          expect(@individual_market_eligibility.is_satisfied).to eq(true)
          expect(@individual_market_eligibility._type).to eq('Eligibilities::V3::IndividualMarketEligibility')
          expect(@individual_market_eligibility.determined_at).to be_present
          expect(@individual_market_eligibility.state_histories.count).to eq(1)
          expect(@individual_market_eligibility.state_histories.first.to_state).to eq(:verification_in_progress)
          expect(@individual_market_eligibility.state_histories.first.from_state).to eq(:initial)
          expect(@individual_market_eligibility.state_histories.first.transition_at).to be_present
          expect(@individual_market_eligibility.state_histories.first.event).to eq(:pend)
          expect(@individual_market_eligibility.state_histories.first.reason).to eq("migrating for the family #{@new_application.family_id} to create individual_market_eligibility")
        end

        context 'should migrate ssn_verification_type' do
          # match verification types with applicant evidence
          it 'should migrate ssn verification type to evidence 3.0' do
            expect(@social_security_number_evidence).to be_present
            expect(@social_security_number_evidence.created_at).to be_present
            expect(@social_security_number_evidence.updated_at).to be_present
            expect(@social_security_number_evidence._type).to eq('Eligibilities::V3::Evidences::SocialSecurityNumberEvidence')
            expect(@social_security_number_evidence.current_state).to eq(@ssn_verification_type.validation_status.to_sym)
            expect(@social_security_number_evidence.is_satisfied).to eq(["outstanding","rejected"].include?(@ssn_verification_type.validation_status) ? false : true)
            expect(@social_security_number_evidence.verification_outstanding).to eq(["outstanding","rejected"].include?(@ssn_verification_type.validation_status))
            expect(@social_security_number_evidence.due_on).to eq(@ssn_verification_type.due_date)
            expect(@social_security_number_evidence.updated_by).to eq(@ssn_verification_type.updated_by)
            expect(@social_security_number_evidence.external_service).to eq(@ssn_verification_type.external_service)
            expect(@social_security_number_evidence.is_active).to eq(!@ssn_verification_type.inactive)
          end

          it 'should create verification_histories' do
            type_history_elements = @type_history_elements.where(:event_response_record_id => nil).order_by("created_at ASC")
            expect(@verification_histories).to be_present
            expect(@verification_histories.count).to eq(type_history_elements.count)
            expect(@verification_histories.map(&:created_at)).to be_present
            expect(@verification_histories.map(&:updated_at)).to be_present
            expect(@verification_histories.map(&:action)).to eq(type_history_elements.map(&:action))
            expect(@verification_histories.map(&:update_reason)).to eq(type_history_elements.map(&:update_reason))
            expect(@verification_histories.map(&:updated_by)).to eq(type_history_elements.map(&:modifier))
            expect(@verification_histories.map(&:date_of_action).flatten.collect{|a| a.strftime("%m/%d/%Y %H:%M %L %:z")}).to eq(type_history_elements.map(&:created_at).flatten.collect{|a| a.strftime("%m/%d/%Y %H:%M %L %:z")})
            latest_verification_history = @verification_histories.order_by("date_of_action DESC").first
            expect(latest_verification_history.is_satisfied).to eq(@social_security_number_evidence.is_satisfied)
            expect(latest_verification_history.verification_outstanding).to eq(@social_security_number_evidence.verification_outstanding)

          end

          it 'should create request_results' do
            type_history_elements = @type_history_elements.where(:event_response_record_id.ne => nil).order_by("created_at ASC")
            responses = consumer_role.lawful_presence_determination.ssa_responses.where(:id.in => type_history_elements.map(&:event_response_record_id))
            expect(@request_results).to be_present
            expect(@request_results.count).to eq(type_history_elements.count)
            expect(@request_results.map(&:created_at)).to be_present
            expect(@request_results.map(&:updated_at)).to be_present
            expect(@request_results.map(&:result).compact.flatten).to be_empty
            expect(@request_results.map(&:source)).to eq(["FDSH"])
            expect(@request_results.map(&:source_transaction_id).compact.flatten).to be_empty
            expect(@request_results.map(&:code)).to eq(["HS000000"])
            expect(@request_results.map(&:code_description)).to eq(["ResponseDescriptionText0"])
            expect(@request_results.map(&:raw_payload)).to eq(responses.map(&:body))

          end

          it 'should create state_histories' do
            expect(@state_histories).not_to be_present
            expect(@state_histories.count).to eq(0)
          end
        end

        context 'should migrate citizenship_verification_type' do
          before do
            @citizenship_verification_type = person.verification_types.citizenship_type.first
            @type_history_elements = @citizenship_verification_type.type_history_elements
            @citizenship_evidence = @individual_market_eligibility.evidences.select { |e| e.key == "citizenship_evidence" }.first
            @verification_histories = @citizenship_evidence.verification_histories
            @request_results = @citizenship_evidence.request_results
            @state_histories = @citizenship_evidence.state_histories
          end
          # match verification types with applicant evidence
          it 'should migrate citizenship verification type to evidence 3.0' do
            expect(@citizenship_evidence).to be_present
            expect(@citizenship_evidence.created_at).to be_present
            expect(@citizenship_evidence.updated_at).to be_present
            expect(@citizenship_evidence._type).to eq('Eligibilities::V3::Evidences::CitizenshipEvidence')
            expect(@citizenship_evidence.current_state).to eq(@citizenship_verification_type.validation_status.to_sym)
            expect(@citizenship_evidence.is_satisfied).to eq(["outstanding","rejected"].include?(@citizenship_verification_type.validation_status) ? false : true)
            expect(@citizenship_evidence.verification_outstanding).to eq(["outstanding","rejected"].include?(@citizenship_verification_type.validation_status))
            expect(@citizenship_evidence.due_on).to eq(@citizenship_verification_type.due_date)
            expect(@citizenship_evidence.updated_by).to eq(@citizenship_verification_type.updated_by)
            expect(@citizenship_evidence.external_service).to eq(@citizenship_verification_type.external_service)
            expect(@citizenship_evidence.is_active).to eq(!@citizenship_verification_type.inactive)
          end

          it 'should create verification_histories' do
            type_history_elements = @type_history_elements.where(:event_response_record_id => nil).order_by("created_at ASC")
            expect(@verification_histories).to be_present
            expect(@verification_histories.count).to eq(type_history_elements.count)
            expect(@verification_histories.map(&:created_at)).to be_present
            expect(@verification_histories.map(&:updated_at)).to be_present
            expect(@verification_histories.map(&:action)).to eq(type_history_elements.map(&:action))
            expect(@verification_histories.map(&:update_reason)).to eq(type_history_elements.map(&:update_reason))
            expect(@verification_histories.map(&:updated_by)).to eq(type_history_elements.map(&:modifier))
            expect(@verification_histories.map(&:date_of_action).flatten.collect{|a| a.strftime("%m/%d/%Y %H:%M %L %:z")}).to eq(type_history_elements.map(&:created_at).flatten.collect{|a| a.strftime("%m/%d/%Y %H:%M %L %:z")})
            latest_verification_history = @verification_histories.order_by("date_of_action DESC").first
            expect(latest_verification_history.is_satisfied).to eq(@citizenship_evidence.is_satisfied)
            expect(latest_verification_history.verification_outstanding).to eq(@citizenship_evidence.verification_outstanding)
          end

          it 'should create request_results' do
            type_history_elements = @type_history_elements.where(:event_response_record_id.ne => nil).order_by("created_at ASC")
            responses = consumer_role.lawful_presence_determination.vlp_responses.where(:id.in => type_history_elements.map(&:event_response_record_id))
            expect(@request_results).to be_present
            expect(@request_results.count).to eq(type_history_elements.count)
            expect(@request_results.map(&:created_at)).to be_present
            expect(@request_results.map(&:updated_at)).to be_present
            expect(@request_results.map(&:result).compact.flatten).to be_empty
            expect(@request_results.map(&:source)).to eq(["FDSH"])
            expect(@request_results.map(&:source_transaction_id).compact.flatten).to be_empty
            expect(@request_results.map(&:code)).to eq(["HS000000"])
            expect(@request_results.map(&:code_description)).to eq(["ResponseDescriptionText0"])
            expect(@request_results.map(&:raw_payload)).to eq(responses.map(&:body))
          end

          it 'should create state_histories' do
            expect(@state_histories).not_to be_present
            expect(@state_histories.count).to eq(0)
          end

          it 'should create documents' do
            expect(@citizenship_evidence.documents).to be_present
            expect(@citizenship_evidence.documents.count).to eq(2)
            expect(@citizenship_evidence.documents.map(&:created_at)).to be_present
            expect(@citizenship_evidence.documents.map(&:updated_at)).to be_present
            expect(@citizenship_evidence.documents.first.id).not_to eq(@citizenship_verification_type.vlp_documents.first.id)
            expect_attributes_to_match(@citizenship_evidence.documents.first, @citizenship_verification_type.vlp_documents.first, [:title, :creator, :subject, :publisher, :type, :identifier, :source, :language])
          end
        end

        context 'should migrate alive_status_verification_type' do
          before do
            @alive_status_verification_type = person.verification_types.alive_status_type.first
            @type_history_elements = @alive_status_verification_type.type_history_elements
            @alive_status_evidence = @individual_market_eligibility.evidences.select { |e| e.key == "alive_evidence" }.first
            @verification_histories = @alive_status_evidence.verification_histories
            @request_results = @alive_status_evidence.request_results
            @state_histories = @alive_status_evidence.state_histories
          end
          # match verification types with applicant evidence
          it 'should migrate alive status verification type to evidence 3.0' do
            alive_status_evidence = @individual_market_eligibility.evidences.select { |e| e.key == "alive_evidence" }.first
            expect(alive_status_evidence).to be_present
            expect(alive_status_evidence.created_at).to be_present
            expect(alive_status_evidence.updated_at).to be_present
            expect(alive_status_evidence._type).to eq('Eligibilities::V3::Evidences::AliveEvidence')
            expect(alive_status_evidence.current_state).to eq(@alive_status_verification_type.validation_status.to_sym)
            expect(alive_status_evidence.is_satisfied).to eq(["outstanding","rejected"].include?(@alive_status_verification_type.validation_status) ? false : true)
            expect(alive_status_evidence.verification_outstanding).to eq(["outstanding","rejected"].include?(@alive_status_verification_type.validation_status))
            expect(alive_status_evidence.due_on).to eq(@alive_status_verification_type.due_date)
            expect(alive_status_evidence.updated_by).to eq(@alive_status_verification_type.updated_by)
            expect(alive_status_evidence.external_service).to eq(@alive_status_verification_type.external_service)
            expect(alive_status_evidence.is_active).to eq(!@alive_status_verification_type.inactive)
          end

          it 'should create verification_histories' do
            type_history_elements = @type_history_elements.where(:event_response_record_id => nil).order_by("created_at ASC")
            expect(@verification_histories).to be_present
            expect(@verification_histories.count).to eq(type_history_elements.count)
            expect(@verification_histories.map(&:created_at)).to be_present
            expect(@verification_histories.map(&:updated_at)).to be_present
            expect(@verification_histories.map(&:action)).to eq(type_history_elements.map(&:action))
            expect(@verification_histories.map(&:update_reason)).to eq(type_history_elements.map(&:update_reason))
            expect(@verification_histories.map(&:updated_by)).to eq(type_history_elements.map(&:modifier))
            expect(@verification_histories.map(&:date_of_action).flatten.collect{|a| a.strftime("%m/%d/%Y %H:%M %L %:z")}).to eq(type_history_elements.map(&:created_at).flatten.collect{|a| a.strftime("%m/%d/%Y %H:%M %L %:z")})
            latest_verification_history = @verification_histories.order_by("date_of_action DESC").first
            expect(latest_verification_history.is_satisfied).to eq(@alive_status_evidence.is_satisfied)
            expect(latest_verification_history.verification_outstanding).to eq(@alive_status_evidence.verification_outstanding)
          end

          it 'should create request_results' do
            type_history_elements = @type_history_elements.where(:event_response_record_id.ne => nil).order_by("created_at ASC")
            responses = consumer_role.alive_status_responses.where(:id.in => type_history_elements.map(&:event_response_record_id))
            expect(@request_results).to be_present
            expect(@request_results.count).to eq(type_history_elements.count)
            expect(@request_results.map(&:created_at)).to be_present
            expect(@request_results.map(&:updated_at)).to be_present
            expect(@request_results.map(&:result).compact.flatten).to be_empty
            expect(@request_results.map(&:source)).to eq(["FDSH"])
            expect(@request_results.map(&:source_transaction_id).compact.flatten).to be_empty
            expect(@request_results.map(&:code)).to eq(["HS000000"])
            expect(@request_results.map(&:code_description)).to eq(["ResponseDescriptionText0"])
            expect(@request_results.map(&:raw_payload)).to eq(responses.map(&:body))
          end

          it 'should create state_histories' do
            type_history_elements = @type_history_elements.where(:event_response_record_id.ne => nil, :to_validation_status.ne => nil).order_by("created_at ASC")
            expect(@state_histories).to be_present
            expect(@state_histories.count).to eq(type_history_elements.count)
            expect(@state_histories.map(&:created_at)).to be_present
            expect(@state_histories.map(&:updated_at)).to be_present
            expect(@state_histories.first.to_state).to eq(type_history_elements.first.to_validation_status.to_sym)
            expect(@state_histories.first.from_state).to eq(@alive_status_verification_type.validation_status.to_sym)
            expect(@state_histories.map(&:effective_on)).to be_present
            expect(@state_histories.first.reason).to eq(type_history_elements.first.update_reason)
            expect(@state_histories.first.created_at).to be_present
            expect(@state_histories.first.transition_at).to be_present
            expect(@state_histories.first.event).to eq(:verify)
          end
        end

        context 'should migrate immigration_verification_type' do
          before do
            @immigration_verification_type = person.verification_types.by_name('Immigration status').first
            @type_history_elements = @immigration_verification_type.type_history_elements
            @immigration_evidence = @individual_market_eligibility.evidences.select { |e| e.key == "immigration_evidence" }.first
            @verification_histories = @immigration_evidence.verification_histories
            @request_results = @immigration_evidence.request_results
            @state_histories = @immigration_evidence.state_histories
          end
          # match verification types with applicant evidence
          it 'should migrate immigration verification type to evidence 3.0' do
            expect(@immigration_evidence).to be_present
            expect(@immigration_evidence.created_at).to be_present
            expect(@immigration_evidence.updated_at).to be_present
            expect(@immigration_evidence._type).to eq('Eligibilities::V3::Evidences::ImmigrationEvidence')
            expect(@immigration_evidence.current_state).to eq(@immigration_verification_type.validation_status.to_sym)
            expect(@immigration_evidence.is_satisfied).to eq(["outstanding","rejected"].include?(@immigration_verification_type.validation_status) ? false : true)
            expect(@immigration_evidence.verification_outstanding).to eq(["outstanding","rejected"].include?(@immigration_verification_type.validation_status))
            expect(@immigration_evidence.due_on).to eq(@immigration_verification_type.due_date)
            expect(@immigration_evidence.updated_by).to eq(@immigration_verification_type.updated_by)
            expect(@immigration_evidence.external_service).to eq(@immigration_verification_type.external_service)
            expect(@immigration_evidence.is_active).to eq(!@immigration_verification_type.inactive)
          end


          it 'should create verification_histories' do
            type_history_elements = @type_history_elements.where(:event_response_record_id => nil).order_by("created_at ASC")
            expect(@verification_histories).to be_present
            expect(@verification_histories.count).to eq(type_history_elements.count)
            expect(@verification_histories.map(&:created_at)).to be_present
            expect(@verification_histories.map(&:updated_at)).to be_present
            expect(@verification_histories.map(&:action)).to eq(type_history_elements.map(&:action))
            expect(@verification_histories.map(&:update_reason)).to eq(type_history_elements.map(&:update_reason))
            expect(@verification_histories.map(&:updated_by)).to eq(type_history_elements.map(&:modifier))
            expect(@verification_histories.map(&:date_of_action).flatten.collect{|a| a.strftime("%m/%d/%Y %H:%M %L %:z")}).to eq(type_history_elements.map(&:created_at).flatten.collect{|a| a.strftime("%m/%d/%Y %H:%M %L %:z")})
            latest_verification_history = @verification_histories.order_by("date_of_action DESC").first
            expect(latest_verification_history.is_satisfied).to eq(@immigration_evidence.is_satisfied)
            expect(latest_verification_history.verification_outstanding).to eq(@immigration_evidence.verification_outstanding)
          end

          it 'should create request_results' do
            type_history_elements = @type_history_elements.where(:event_response_record_id.ne => nil).order_by("created_at ASC")
            responses = consumer_role.lawful_presence_determination.vlp_responses.where(:id.in => type_history_elements.map(&:event_response_record_id))
            expect(@request_results).to be_present
            expect(@request_results.count).to eq(type_history_elements.count)
            expect(@request_results.map(&:created_at)).to be_present
            expect(@request_results.map(&:updated_at)).to be_present
            expect(@request_results.map(&:result).compact.flatten).to be_empty
            expect(@request_results.map(&:source)).to eq(["FDSH"])
            expect(@request_results.map(&:source_transaction_id).compact.flatten).to be_empty
            expect(@request_results.map(&:code)).to eq(["HS000000"])
            expect(@request_results.map(&:code_description)).to eq(["ResponseDescriptionText0"])
            expect(@request_results.map(&:raw_payload)).to eq(responses.map(&:body))
          end

          it 'should create documents' do
            expect(@immigration_evidence.documents).to be_present
            expect(@immigration_evidence.documents.count).to eq(2)
            expect(@immigration_evidence.documents.map(&:created_at)).to be_present
            expect(@immigration_evidence.documents.map(&:updated_at)).to be_present
            expect_attributes_to_match(@immigration_evidence.documents.first, @immigration_verification_type.vlp_documents.first, [:title, :creator, :subject, :publisher, :type, :identifier, :source, :language])
          end
        end
      end

      context 'should migrate aptc csr eligibility' do
        before do
          @result = subject.call({document_id: application.id.to_s})
          @old_applicant = application.applicants.first
          @new_application_hbx_id = @result.value![1]
          @new_application = FinancialAssistance::Application.where(hbx_id: @new_application_hbx_id).first
          @new_application.reload
          @new_applicant = @new_application.applicants.first
          @individual_market_eligibility = @new_applicant.individual_market_eligibility
          new_application_hbx_id = @result.value![1]
          new_application = FinancialAssistance::Application.where(hbx_id: new_application_hbx_id).first
          @new_aptc_csr_eligibility = new_application.applicants.first.aptc_csr_eligibility
          @old_aptc_csr_eligibility = application.applicants.first.aptc_csr_eligibility
          @old_income_evidence = application.applicants.first.aptc_csr_eligibility.evidences.first
          @new_income_evidence = @new_aptc_csr_eligibility.evidences.first
        end
        it 'should create aptc csr eligibility' do
          expect(@new_aptc_csr_eligibility).to be_present
          expect(@new_aptc_csr_eligibility.evidences.count).to eq(@old_aptc_csr_eligibility.evidences.count)
          expect(@new_aptc_csr_eligibility.created_at).to be_present
          expect(@new_aptc_csr_eligibility.updated_at).to be_present
          expect(@new_aptc_csr_eligibility.current_state).to eq(@old_aptc_csr_eligibility.current_state)
          expect(@new_aptc_csr_eligibility.is_satisfied).to eq(@old_aptc_csr_eligibility.is_satisfied)
          expect(@new_aptc_csr_eligibility._type).to eq('Eligibilities::V3::AptcCsrEligibility')
          expect(@new_aptc_csr_eligibility.determined_at).to eq(@old_aptc_csr_eligibility.determined_at)
          expect(@new_aptc_csr_eligibility.state_histories.count).to eq(@old_aptc_csr_eligibility.state_histories.count)
          new_state_histories = @new_aptc_csr_eligibility.state_histories.first
          old_state_histories = @old_aptc_csr_eligibility.state_histories.first
          expect(new_state_histories.transition_at.strftime("%m/%d/%Y %I:%M%p")).to eq(old_state_histories.transition_at.strftime("%m/%d/%Y %I:%M%p"))
          expect_attributes_to_match(new_state_histories, old_state_histories, [:to_state, :from_state, :event, :reason])
        end

        it 'should migrate evidence 1.0 to 3.0' do
          expect(@new_income_evidence.id).not_to eq(@old_income_evidence.id)
          expect(@new_income_evidence.created_at).to be_present
          expect(@new_income_evidence.updated_at).to be_present
          expect(@new_income_evidence.key.to_s).to eq(@old_income_evidence.key)
          expect(@new_income_evidence._type).to eq('FinancialAssistance::Evidences::IncomeEvidence')
          expect(@new_income_evidence.verification_histories.count).to eq(@old_income_evidence.verification_histories.count)
          expect_attributes_to_match(@new_income_evidence, @old_income_evidence, [:title, :current_state, :verification_outstanding, :due_on, :is_satisfied, :updated_by, :external_service, :determined_at])
        end

        it 'should migrate verification history 1.0 to 3.0' do
          old_verification_histories = @old_income_evidence.verification_histories
          new_verification_histories = @new_income_evidence.verification_histories
          expect(new_verification_histories.count).to eq(old_verification_histories.count)
          expect(new_verification_histories.map(&:action)).to eq(old_verification_histories.map(&:action))
          new_verification_history = new_verification_histories.first
          old_verification_history = old_verification_histories.first
          expect(new_verification_history.created_at).to be_present
          expect(new_verification_history.updated_at).to be_present
          expect(new_verification_history.id).not_to eq(old_verification_history.id)
          expect_attributes_to_match(new_verification_history, old_verification_history, [:action, :update_reason, :updated_by, :is_satisfied, :verification_outstanding, :due_on])
        end


        it 'should migrate request result 1.0 to 3.0' do
          old_request_results = @old_income_evidence.request_results
          new_request_results = @new_income_evidence.request_results
          expect(new_request_results.count).to eq(old_request_results.count)
          new_request_result = new_request_results.first
          old_request_result = old_request_results.first
          expect(new_request_result.created_at).to be_present
          expect(new_request_result.updated_at).to be_present
          expect(new_request_result.id).not_to eq(old_request_result.id)
          expect(new_request_result.date_of_action.strftime("%m/%d/%Y %I:%M%p")).to eq(old_request_result.date_of_action.strftime("%m/%d/%Y %I:%M%p"))
          expect_attributes_to_match(new_request_result, old_request_result, [:result, :source, :source_transaction_id, :code, :code_description, :raw_payload, :action])
        end

        it 'should migrate workflow state transition 1.0 to 3.0' do
          old_state_transitions = @old_income_evidence.state_histories
          new_state_transitions = @new_income_evidence.state_histories
          expect(new_state_transitions.count).to eq(old_state_transitions.count)
          expect(new_state_transitions.map(&:to_state)).to eq(old_state_transitions.map(&:to_state).map(&:to_sym))
          new_state_transition = new_state_transitions.first
          old_state_transition = old_state_transitions.first
          expect(new_state_transition.created_at).to be_present
          expect(new_state_transition.updated_at).to be_present
          expect(new_state_transition.id).not_to eq(old_state_transition.id)
          expect(new_state_transition.transition_at.strftime("%m/%d/%Y %I:%M%p")).to eq(new_state_transition.transition_at.strftime("%m/%d/%Y %I:%M%p"))
          expect_attributes_to_match(new_state_transition, old_state_transition, [:to_state, :from_state, :event, :reason, :effective_on, :is_eligible, :metadata])
        end

        it 'should migrate evidence documents from 1.0 to 3.0' do
          old_income_evidence_documents = @old_income_evidence.documents
          new_income_evidence_documents = @new_income_evidence.documents
          expect(new_income_evidence_documents.count).to eq(old_income_evidence_documents.count)
          new_income_evidence_document = new_income_evidence_documents.first
          old_income_evidence_document = old_income_evidence_documents.first
          expect(new_income_evidence_document.created_at).to be_present
          expect(new_income_evidence_document.updated_at).to be_present
          expect(new_income_evidence_document.id).not_to eq(old_income_evidence_document.id)
          expect_attributes_to_match(new_income_evidence_document, old_income_evidence_document, [:title, :creator, :subject, :publisher, :type, :identifier, :source, :language])
        end
      end

      context 'do not sync applicants' do
        before do
          family_member
          family_member2
          family.primary_person.ensure_relationship_with(person2, 'spouse')
          family.primary_person.ensure_relationship_with(person3, 'child')
          @result = subject.call({document_id: application.id.to_s})
          @old_applicant = application.applicants.first
          @new_application_hbx_id = @result.value![1]
          @new_application = FinancialAssistance::Application.where(hbx_id: @new_application_hbx_id).first
          @new_application.reload
          @new_applicant = @new_application.applicants.first
          @individual_market_eligibility = @new_applicant.individual_market_eligibility
        end

        let(:person2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, age_off_excluded: true) }
        let(:person3) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, age_off_excluded: true) }
        let!(:family_member) { FactoryBot.create(:family_member, family: family, person: person2) }
        let!(:family_member2) { FactoryBot.create(:family_member, family: family, person: person3) }

        it 'should not sync applicants' do
          expect(family.family_members.count).to eq(3)
          expect(@new_application.applicants.count).to eq(1)
          new_applicant = @new_application.applicants.first
          expect(new_applicant.person_hbx_id).to eq(person.hbx_id)
          expect(new_applicant.family_member_id).to eq(family.family_members.first.id)
          expect(new_applicant.age_off_excluded).to eq(person.age_off_excluded)
          expect(@new_application.applicants.map(&:person_hbx_id)).not_to include(person2.hbx_id, person3.hbx_id)
          expect(new_applicant.eligibility_determination_id).not_to be(@old_applicant.eligibility_determination_id)
          expect_attributes_to_match(new_applicant, @old_applicant, [:name_pfx, :first_name, :middle_name, :last_name, :name_sfx, :encrypted_ssn, :gender, :dob, :is_primary_applicant,
                                                                     :is_incarcerated, :is_disabled, :ethnicity, :race, :indian_tribe_member, :tribal_id, :language_code, :no_dc_address,
                                                                     :is_homeless, :is_temporarily_out_of_state, :immigration_doc_statuses, :no_ssn, :citizen_status, :is_consumer_role,
                                                                     :is_resident_role, :same_with_primary, :is_applying_coverage, :is_tobacco_user, :vlp_document_id, :vlp_subject,
                                                                     :alien_number, :i94_number, :visa_number, :passport_number, :sevis_id, :naturalization_number, :receipt_number,
                                                                     :citizenship_number, :card_number, :country_of_citizenship, :vlp_description, :expiration_date, :issuing_country,
                                                                     :is_consent_applicant, :is_tobacco_user, :assisted_income_validation, :assisted_mec_validation, :assisted_income_reason,
                                                                     :assisted_mec_reason, :aasm_state, :person_hbx_id, :ext_app_id, :family_member_id, :has_fixed_address, :is_living_in_state,
                                                                     :is_required_to_file_taxes, :is_filing_as_head_of_household, :tax_filer_kind, :is_joint_tax_filing, :is_claimed_as_tax_dependent,
                                                                     :is_physically_disabled, :has_income_verification_response, :has_mec_verification_response, :is_medicare_eligible, :is_student,
                                                                     :student_kind, :student_school_kind, :student_status_end_on, :is_self_attested_blind, :is_self_attested_disabled,
                                                                     :is_self_attested_long_term_care, :is_veteran, :is_refugee, :is_trafficking_victim, :is_former_foster_care, :age_left_foster_care,
                                                                     :foster_care_us_state, :had_medicaid_during_foster_care, :is_pregnant, :is_enrolled_on_medicaid, :is_post_partum_period,
                                                                     :children_expected_count, :pregnancy_due_on, :pregnancy_end_on, :is_primary_caregiver, :is_subject_to_five_year_bar,
                                                                     :is_five_year_bar_met, :is_forty_quarters, :is_ssn_applied, :non_ssn_apply_reason, :moved_on_or_after_welfare_reformed_law,
                                                                     :is_veteran_or_active_military, :is_spouse_or_dep_child_of_veteran_or_active_military, :is_currently_enrolled_in_health_plan,
                                                                     :has_daily_living_help, :need_help_paying_bills, :is_resident_post_092296, :is_vets_spouse_or_child, :has_job_income,
                                                                     :has_self_employment_income, :has_other_income, :has_unemployment_income, :has_deductions, :has_enrolled_health_coverage,
                                                                     :has_eligible_health_coverage, :has_american_indian_alaskan_native_income, :medicaid_chip_ineligible, :immigration_status_changed,
                                                                     :health_service_through_referral, :health_service_eligible, :tribal_state, :tribal_name, :tribe_codes, :is_medicaid_cubcare_eligible,
                                                                     :has_eligible_medicaid_cubcare, :medicaid_cubcare_due_on, :has_eligibility_changed, :has_household_income_changed,
                                                                     :person_coverage_end_on, :has_dependent_with_coverage, :dependent_job_end_on, :transfer_referral_reason,
                                                                     :five_year_bar_applies, :five_year_bar_met, :qualified_non_citizen, :is_eligible_for_non_magi_reasons, :magi_medicaid_category, :medicaid_household_size,
                                                                     :magi_medicaid_monthly_household_income, :magi_medicaid_monthly_income_limit, :magi_as_percentage_of_fpl, :csr_percent_as_integer, :csr_eligibility_kind,
                                                                     :benchmark_premiums, :contact_method, :language_preference, :is_ia_eligible, :is_csr_eligible, :is_medicaid_chip_eligible,
                                                                     :is_non_magi_medicaid_eligible, :is_totally_ineligible, :is_without_assistance, :is_magi_medicaid])
        end
      end

      context 'income evidence' do
        let!(:v3_verification_history_auto_extended1)  { FactoryBot.create(:v3_verification_history, evidence: evidence, action: 'auto_extend_due_date', date_of_action: Time.current + 1.day) }
        let!(:v3_verification_history_auto_extended2)  { FactoryBot.create(:v3_verification_history, evidence: evidence, action: 'auto_extend_due_date', date_of_action: Time.current) }

        it 'should create family_determination and populate due_date_extended_at' do
          expect(family.eligibility_determination).not_to be_present
          result = subject.call({document_id: application.id.to_s})
          new_application_hbx_id = result.value![1]
          new_application = FinancialAssistance::Application.where(hbx_id: new_application_hbx_id).first
          new_applicant = new_application.applicants.first
          new_aptc_csr_eligibility = new_applicant.aptc_csr_eligibility
          new_income_evidence = new_aptc_csr_eligibility.income_evidence
          expect(new_income_evidence.due_date_extended_at).to be_present
          expect(new_income_evidence.due_date_extended_at.strftime("%m/%d/%Y %I:%M%p")).to eq(v3_verification_history_auto_extended1.date_of_action.strftime("%m/%d/%Y %I:%M%p"))
          family.reload
          expect(family.eligibility_determination).to be_present
          expect(family.eligibility_determination.subjects.count).to eq(1)
        end
      end

      context "esi evidence" do
        let!(:esi_evidence) do
          FactoryBot.create(:esi_mec_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::EsiMecEvidence',key: :esi_mec_evidence, title: 'Esi MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                               description: 'EsiMecEvidence', current_state: "pending")
        end
        let!(:old_state_history) { FactoryBot.create(:v3_state_history, status_trackable: esi_evidence, created_at: 2.days.ago) }
        let!(:new_state_history) { FactoryBot.create(:v3_state_history, status_trackable: esi_evidence, created_at: 1.day.ago) }
        let!(:v3_verification_history)  { FactoryBot.create(:v3_verification_history, evidence: esi_evidence) }
        let!(:v3_request_result)  { FactoryBot.create(:v3_request_result, evidence: esi_evidence) }
        let!(:v3_verification_history_auto_extended1)  { FactoryBot.create(:v3_verification_history, evidence: esi_evidence, action: 'auto_extend_due_date', date_of_action: Time.current + 1.day) }
        let!(:v3_verification_history_auto_extended2)  { FactoryBot.create(:v3_verification_history, evidence: esi_evidence, action: 'auto_extend_due_date', date_of_action: Time.current) }

        it 'should create family_determination but not populate due_date_extended_at' do
          expect(family.eligibility_determination).not_to be_present
          result = subject.call({document_id: application.id.to_s})
          new_application_hbx_id = result.value![1]
          new_application = FinancialAssistance::Application.where(hbx_id: new_application_hbx_id).first
          new_applicant = new_application.applicants.first
          new_aptc_csr_eligibility = new_applicant.aptc_csr_eligibility
          new_esi_evidence = new_aptc_csr_eligibility.esi_mec_evidence
          expect(new_esi_evidence.due_date_extended_at).not_to be_present
          family.reload
          expect(family.eligibility_determination).to be_present
          expect(family.eligibility_determination.subjects.count).to eq(1)
        end
      end
    end

    context 'failed case' do
      context 'old applicant without aptc csr eligibility' do
        before do
          allow(EnrollRegistry[:alive_status].feature).to receive(:is_enabled).and_return(true)
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
          consumer_role.save!
          person.verification_types.where(type_name: "DC Residency").delete_all
          person2.verification_types.where(type_name: "DC Residency").delete_all
          person3.verification_types.where(type_name: "DC Residency").delete_all
          person.verification_types.alive_status_type.each do |verification_type|
            verification_type.add_type_history_element(action: "FDSH alive status Hub Response",
                                                       modifier: "external Hub",
                                                       update_reason: "Hub response",
                                                       event_response_record_id: response3.id,
                                                       to_validation_status: "verified",
                                                       from_validation_status: "unverified",
                                                       created_at: DateTime.now)

            verification_type.add_type_history_element(action: "call hub",
                                                       modifier: "admin",
                                                       update_reason: "Hub request",
                                                       event_response_record_id: nil,
                                                       created_at: DateTime.now - 5.minutes)
            verification_type.save!
          end
          family_member2
          applicant2
          @result = subject.call({document_id: application.id.to_s})
          @old_applicant = application.applicants.first
        end

        let(:person2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, age_off_excluded: true) }
        let(:person3) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, age_off_excluded: true) }
        let!(:family_member2) { FactoryBot.create(:family_member, family: family, person: person2) }
        let!(:family_member3) { FactoryBot.create(:family_member, family: family, person: person3) }
        let!(:applicant2) do
          FactoryBot.create(:applicant,
                            application: application,
                            dob: TimeKeeper.date_of_record - 40.years,
                            is_primary_applicant: true,
                            family_member_id: family.family_members[1].id,
                            person_hbx_id: person2.hbx_id,
                            addresses: [FactoryBot.build(:financial_assistance_address)])
        end

        it 'should fail' do
          expect(@result.failure?).to be_truthy
          expect(@result.failure.to_s).to eq("generation failed for the application: #{application.hbx_id} with error: No APTC/CSR eligibility object found for old applicant #{applicant2.person_hbx_id}")
        end
      end
    end
  end
end

def expect_attributes_to_match(new_object, old_object, attributes)
  attributes.each do |attribute|
    expect(new_object.send(attribute)).to eq(old_object.send(attribute))
  end
end