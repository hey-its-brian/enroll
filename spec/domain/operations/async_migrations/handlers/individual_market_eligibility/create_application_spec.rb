# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::CreateApplication, dbclean: :after_each do
  include Dry::Monads[:do, :result]

  let!(:hbx_profile)   { FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period) }
  let!(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
  let!(:benefit_coverage_period) { hbx_profile.benefit_sponsorship.benefit_coverage_periods.first }
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, no_ssn: false, age_off_excluded: true) }
  let(:consumer_role) do
    consumer = person.consumer_role
    consumer.contact_method = "Paper and Electronic communications"
    consumer.language_preference = "test"
    consumer.save!
    consumer
  end
  let!(:immigration_type) do
    immigration = FactoryBot.build(:verification_type, type_name: 'Immigration status',
                                                       validation_status: 'rejected',
                                                       applied_roles: ['consumer_role'],
                                                       update_reason: 'initial',
                                                       rejected: false,
                                                       external_service: 'some_service',
                                                       due_date: Date.today,
                                                       due_date_type: 'admin',
                                                       updated_by: 'admin',
                                                       inactive: true)
    person.verification_types << immigration
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

  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:product) {FactoryBot.create(:benefit_markets_products_health_products_health_product, benefit_market_kind: :aca_individual, kind: :health, csr_variant_id: '01')}
  let(:effective_on) { TimeKeeper.date_of_record.beginning_of_year}
  let!(:active_enrollment) do
    FactoryBot.create(:hbx_enrollment,
                      family: family,
                      household: family.active_household,
                      kind: "individual",
                      coverage_kind: "health",
                      product: product,
                      aasm_state: 'coverage_selected',
                      effective_on: effective_on,
                      hbx_enrollment_members: [
                        FactoryBot.build(:hbx_enrollment_member, applicant_id: family.primary_applicant.id, eligibility_date: effective_on, coverage_start_on: effective_on, is_subscriber: true)
                      ])
  end

  context '#migration creates family eligibility determination' do
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

    it 'should create family_determination' do
      expect(family.eligibility_determination).not_to be_present
      subject.call({document_id: family.id.to_s})
      family.reload
      expect(family.eligibility_determination).to be_present
      expect(family.eligibility_determination.subjects.count).to eq(1)
      subject = family.eligibility_determination.subjects.first
      expect(subject.eligibility_states[0].eligibility_item_key).to eq("aptc_csr_credit")
      expect(subject.eligibility_states[0].evidence_states.count).to eq(0)
      expect(subject.eligibility_states[1].eligibility_item_key).to eq("aca_individual_market_eligibility")
      expect(subject.eligibility_states[1].evidence_states.count).to eq(4)
    end
  end

  context 'when family has FAApplication' do
    let!(:application) do
      FactoryBot.create(:application,
                        family_id: family.id,
                        aasm_state: "determined",
                        effective_date: (TimeKeeper.date_of_record - 12.days),
                        origin: :user,
                        assistance_year: TimeKeeper.date_of_record.year,
                        generation_reason: :manual)
    end

    let!(:eligibility_determination1) { FactoryBot.create(:financial_assistance_eligibility_determination, application: application) }

    let!(:applicant) do
      FactoryBot.create(:applicant,
                        first_name: "app_nmae",
                        application: application,
                        dob: TimeKeeper.date_of_record - 40.years,
                        is_primary_applicant: true,
                        family_member_id: family.family_members[0].id,
                        person_hbx_id: person.hbx_id,
                        addresses: [FactoryBot.build(:financial_assistance_address)],
                        eligibility_determination_id: eligibility_determination1.id)
    end

    before do
      allow(EnrollRegistry[:alive_status].feature).to receive(:is_enabled).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
    end

    it 'should not create individual_market_eligibility' do
      family.assign_latest_application_gid
      expect(family.latest_application).to eq(application)
      expect(family.latest_application_gid).to eq(application.to_global_id.to_s)
      expect { subject.call({document_id: family.id}) }.not_to change(IndividualMarket::Application, :count)
      result = subject.call({document_id: family.id})
      expect(result).to be_failure
      expect(result.failure).to eq("Family with id: #{family.id} is not eligible for migration, determined financial assistance applications exist for assistance year #{TimeKeeper.date_of_record.year}")
    end
  end

  context 'when family does not have hbx enrollments' do
    before do
      allow(EnrollRegistry[:alive_status].feature).to receive(:is_enabled).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
    end

    it 'should not create individual_market_eligibility' do
      family.hbx_enrollments.destroy_all
      result = subject.call({document_id: family.id})
      expect(result).to be_failure
      expect(result.failure).to eq("Family with id: #{family.id} is not eligible for migration, valid hbx enrollments does not exist")
    end
  end

  context '#migration - others' do
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

      @result = subject.call({document_id: family.id})
      @new_application_hbx_id = @result.value![1]
      @new_application = IndividualMarket::Application.where(hbx_id: @new_application_hbx_id).first
      @new_applicant = @new_application.applicants.first
      @individual_market_eligibility = @new_applicant.individual_market_eligibility

    end

    it 'should be a success' do
      expect(@result).to be_success
      expect(@new_application.origin).to eq(:migration)
      expect(@new_application.generation_reason).to eq(:manual)
      expect(@new_application.hbx_id).to be_present
      expect(@new_application.submitted_at).to be_a(DateTime)
      expect(@new_application.submitted_at.utc?).to be true
      expect(@new_application.current_state).to eq(:determined)
      family.reload
      expect(family.latest_application_gid).to eq(@new_application.to_global_id.to_s)
    end

    it 'should migrate contact method, language preference and age off excluded' do
      expect(@new_applicant.age_off_excluded).to eq(person.age_off_excluded)
      expect(@new_applicant.contact_method).to eq(consumer_role.contact_method)
      expect(@new_applicant.language_preference).to eq(consumer_role.language_preference)
    end

    context 'when script is triggered again' do
      it 'should not create a new application' do
        expect { subject.call({document_id: family.id})}.not_to(change { IndividualMarket::Application.count})
      end

      it 'should return error message' do
        result = subject.call({document_id: family.id})
        expect(result).to be_failure
        expect(result.failure).to eq("Family with id: #{family.id} is not eligible for migration, QHP application exists")
      end
    end

    context 'should migrate individual_market_eligibility' do
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
        before do
          @ssn_verification_type = person.verification_types.ssn_type.first
          @type_history_elements = @ssn_verification_type.type_history_elements
          @social_security_number_evidence = @individual_market_eligibility.evidences.select { |e| e.key == "social_security_number_evidence" }.first
          @verification_histories = @social_security_number_evidence.verification_histories
          @request_results = @social_security_number_evidence.request_results
          @state_histories = @social_security_number_evidence.state_histories
        end
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
  end
end

def expect_attributes_to_match(new_object, old_object, attributes)
  attributes.each do |attribute|
    expect(new_object.send(attribute)).to eq(old_object.send(attribute))
  end
end