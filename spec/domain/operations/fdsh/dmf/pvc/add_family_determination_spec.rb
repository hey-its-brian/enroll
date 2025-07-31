# frozen_string_literal: true

require 'rails_helper'
require 'shared_contexts/dual_applications_with_eligible_family_setup'

RSpec.describe Operations::Fdsh::Dmf::Pvc::AddFamilyDetermination, dbclean: :after_each do
  context 'for families with no determined applications' do
    let(:person) do
      p = FactoryBot.create(:person, :with_consumer_role, hbx_id: cv3_family_payload[:family_members][0][:person][:hbx_id])
      p.update_attributes(ssn: cv3_family_payload[:family_members][0][:person][:person_demographics][:ssn])
      p
    end
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, hbx_assigned_id: cv3_family_payload[:hbx_id], person: person) }
    let(:job) { FactoryBot.create(:transmittable_job, :dmf_determination) }
    let(:file_data) { File.read("spec/test_data/dmf_payloads/dmf_response_cv_payload.json") }
    let(:cv3_family_payload) { JSON.parse(JSON.parse(file_data),symbolize_names: true)  }
    let(:encrypted_family_payload) { AcaEntities::Operations::Encryption::Encrypt.new.call(value: JSON.parse(file_data)).value! }

    before do
      allow(EnrollRegistry[:alive_status].feature).to receive(:is_enabled).and_return(true)
      person.build_demographics_group
    end

    context "when member is not enrolled" do
      before do
        @result = described_class.new.call({encrypted_family_payload: encrypted_family_payload, job_id: job.job_id, family_hbx_id: family.hbx_assigned_id})
        person.reload
        family.reload
      end

      it "should set the verification status to NRR" do
        alive_status = person.demographics_group.alive_status
        alive_status_type = person.verification_types.last
        expect(@result).to be_success
        expect(alive_status_type.validation_status).to eq("negative_response_received")
        expect(alive_status.is_deceased).to be_truthy
        expect(alive_status.date_of_death.present?).to be_truthy
      end

      it "should set the family eligibility determination objects" do
        expect(family.eligibility_determination.outstanding_verification_status).to eq("not_enrolled")
        expect(family.eligibility_determination.subjects[0].eligibility_states[1].evidence_states.last.status).to eq(:negative_response_received)
      end
    end

    context "when member is enrolled" do
      let(:hbx_enrollment_member) do
        FactoryBot.build(:hbx_enrollment_member,
                         is_subscriber: true,
                         applicant_id: family.family_members.first.id,
                         coverage_start_on: TimeKeeper.date_of_record.beginning_of_month,
                         eligibility_date: TimeKeeper.date_of_record.beginning_of_month)
      end

      let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, metal_level_kind: :silver, benefit_market_kind: :aca_individual) }
      let!(:enrollment) do
        hbx_enrollment = FactoryBot.create(:hbx_enrollment,
                                           product: product,
                                           family: family,
                                           household: family.active_household,
                                           hbx_enrollment_members: [hbx_enrollment_member],
                                           aasm_state: "coverage_selected",
                                           kind: "individual",
                                           effective_on: TimeKeeper.date_of_record,
                                           rating_area_id: person.consumer_role.rating_address.id,
                                           consumer_role_id: person.consumer_role.id)
        hbx_enrollment.save!
        hbx_enrollment
      end

      before do
        @result = described_class.new.call({encrypted_family_payload: encrypted_family_payload, job_id: job.job_id, family_hbx_id: family.hbx_assigned_id})
        person.reload
        family.reload
        @alive_status = person.demographics_group.alive_status
        @alive_status_type = person.verification_types.alive_status_type.last
        @type_history_element = @alive_status_type.type_history_elements.first
      end

      it "should set the alive evidence to outstanding" do
        expect(@result).to be_success
        expect(@alive_status_type.validation_status).to eq("outstanding")
        expect(@alive_status.is_deceased).to be_truthy
        expect(@alive_status.date_of_death.present?).to be_truthy
      end

      it "should add request results" do
        expect(@alive_status_type.type_history_elements.count).to eq(1)
        expect(@type_history_element.action).to eq("DMF Hub Response")
        expect(@type_history_element.from_validation_status).to eq("unverified")
        expect(@type_history_element.to_validation_status).to eq("outstanding")
        expect(person.consumer_role.alive_status_responses.count).to eq(1)
        expect(JSON.parse(person.consumer_role.alive_status_responses.first.body)).to eq({"job_id" => job.job_id, "family_hbx_id" => family.hbx_assigned_id.to_s, "death_confirmation_code" => "Confirmed", "date_of_death" => "2024-07-03"})
        expect(person.consumer_role.alive_status_responses.first.id.to_s).to eq(@type_history_element.event_response_record_id)
      end

      it "should set the family eligibility determination objects" do
        expect(family.eligibility_determination.outstanding_verification_status).to eq("outstanding")
        expect(family.eligibility_determination.subjects[0].eligibility_states[1].evidence_states.last.status).to eq(:outstanding)
      end
    end

    context "when alive status type is not present in entity" do
      before do
        @result = described_class.new.call({encrypted_family_payload: encrypted_family_payload, job_id: job.job_id, family_hbx_id: family.hbx_assigned_id})
        person.reload
        family.reload
        job.reload
      end

      it "should not record error in transmission" do
        transmission = job.transmissions.first
        transmittable_errors = transmission.transmittable_errors
        latest_state = transmission.process_status.latest_state

        expect(transmittable_errors).to be_empty
        expect(latest_state).to eq(:succeeded)
      end
    end
  end

  context 'for families with determined applications' do
    shared_examples "processes DMF determination for application" do |application_type|
      before do
        allow(EnrollRegistry[:alive_status].feature).to receive(:is_enabled).and_return(true)

        family.update_attributes(hbx_assigned_id: cv3_family_payload[:hbx_id])
        primary_person.update_attributes(hbx_id: cv3_family_payload[:family_members][0][:person][:hbx_id])
        non_primary_person.update_attributes(hbx_id: cv3_family_payload[:family_members][1][:person][:hbx_id])
        primary_person.build_demographics_group
        non_primary_person.build_demographics_group

        app_alias = (application_type == 'faa' ? 'magi_medicaid' : 'individual_market')
        key = "#{app_alias}_applications".to_sym
        @application_hbx_id = cv3_family_payload[key].first[:hbx_id]
      end

      let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, metal_level_kind: :silver, benefit_market_kind: :aca_individual) }
      let(:hbx_enrollment_member1) do
        FactoryBot.build(:hbx_enrollment_member,
                         is_subscriber: true,
                         applicant_id: family.family_members[0].id,
                         coverage_start_on: TimeKeeper.date_of_record.beginning_of_month,
                         eligibility_date: TimeKeeper.date_of_record.beginning_of_month)
      end

      let(:hbx_enrollment_member2) do
        non_primary_family_member
        FactoryBot.build(:hbx_enrollment_member,
                         is_subscriber: true,
                         applicant_id: family.family_members[1].id,
                         coverage_start_on: TimeKeeper.date_of_record.beginning_of_month,
                         eligibility_date: TimeKeeper.date_of_record.beginning_of_month)
      end
      let!(:enrollment) do
        FactoryBot.create(:hbx_enrollment,
                          :with_enrollment_members,
                          product: product,
                          family: family,
                          household: family.active_household,
                          hbx_enrollment_members: [hbx_enrollment_member1, hbx_enrollment_member2],
                          aasm_state: "coverage_selected",
                          kind: "individual",
                          effective_on: TimeKeeper.date_of_record,
                          rating_area_id: primary_person.consumer_role.rating_address.id,
                          consumer_role_id: primary_person.consumer_role.id)
      end

      include_context 'dual applications with eligible family setup'

      let(:current_application) do
        application_type == 'faa' ? create_financial_assistance_application : create_individual_market_application
      end

      let(:file_data) do
        file_name = application_type == 'faa' ? 'dmf_response_cv_payload_with_determined_faa.json' : 'dmf_response_cv_payload_with_determined_qhp.json'
        File.read("spec/test_data/dmf_payloads/#{file_name}")
      end

      let(:cv3_family_payload) do
        payload = JSON.parse(JSON.parse(file_data), symbolize_names: true)
        payload[:hbx_id] = payload[:hbx_id].to_i
        payload
      end
      let(:encrypted_family_payload) { AcaEntities::Operations::Encryption::Encrypt.new.call(value: JSON.parse(file_data)).value! }
      let(:job) { FactoryBot.create(:transmittable_job, :dmf_determination) }
      let(:params) do
        {
          encrypted_family_payload: encrypted_family_payload,
          job_id: job.job_id,
          family_hbx_id: family.hbx_assigned_id,
          application_hbx_id: @application_hbx_id,
          application_type: application_type
        }
      end

      before do
        @result = described_class.new.call(params)
        primary_person.reload
        family.reload
        current_application.reload
      end

      it 'should be success' do
        expect(@result).to be_success
      end

      it 'should update alive_status' do
        alive_status = primary_person.demographics_group.alive_status

        expect(alive_status.is_deceased).to be_truthy
        expect(alive_status.date_of_death.present?).to be_truthy
      end

      it "should update alive_evidence with dates and current_state to 'outstanding'" do
        applicant = current_application.applicants.first
        alive_evidence = applicant.individual_market_eligibility.alive_evidence

        expect(alive_evidence.due_on).to be_present
        expect(alive_evidence.due_on_type).to be_present
        expect(alive_evidence.current_state).to eq(:outstanding)
      end

      it 'should add request results' do
        applicant = current_application.applicants.first
        alive_evidence = applicant.individual_market_eligibility.alive_evidence

        expect(alive_evidence.request_results.count).to eq(1)

        request_result = alive_evidence.request_results.first
        expect(request_result.result).to eq('outstanding')
        expect(request_result.source).to eq('DMF Call Response')
      end

      it 'should set the family eligibility determination objects' do
        expect(family.eligibility_determination.outstanding_verification_status).to eq("outstanding")
      end
    end

    context 'when a family has determined applications' do

      context 'updating response for a family with magi_medicaid most recent determined application' do
        include_examples 'processes DMF determination for application', 'faa'
      end

      context 'updating response for a family with individual_market most recent determined application' do
        include_examples 'processes DMF determination for application', 'qhp'
      end
    end
  end
end
