# frozen_string_literal: true

require 'rails_helper'
RSpec.describe ::Operations::People::BulkHubCallsForVerificationTypes, dbclean: :after_each do

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

  let(:params) { {hbx_ids: [person.hbx_id], verification_type_names: ['Social Security Number']} }

  context 'valid params' do
    before do
      @result = ::Operations::People::BulkHubCallsForVerificationTypes.new.call(params)
    end

    it 'should return a success object' do
      expect(@result.success?).to be_truthy
    end

    it 'should return a success message' do
      expect(@result.success).to eq([[person.hbx_id, person.verification_types.ssn_type.first.type_name, "not eligible for hub call"]])
    end
  end

  context 'invalid params' do
    let(:params) { {hbx_ids: [], verification_type_names: []} }

    before do
      @result = ::Operations::People::BulkHubCallsForVerificationTypes.new.call(params)
    end

    it 'should return a failure object' do
      expect(@result.failure?).to be_truthy
    end

    it 'should return a failure message' do
      expect(@result.failure).to eq('No hbx_ids provided')
    end
  end

  context 'when there is response payload' do
    let(:response_payload_with_all_true) do
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

    let(:entity_response_payload_with_all_true) do
      AcaEntities::Fdsh::Ssa::H3::SSACompositeResponse.new(response_payload_with_all_true)
    end

    before do
      person.consumer_role.lawful_presence_determination.ssa_responses << EventResponse.new({received_at: Time.now, body: entity_response_payload_with_all_true.to_h.to_json})
      person.save!
      response = person.consumer_role.lawful_presence_determination.ssa_responses.first
      person.verification_types.ssn_type.first.add_type_history_element(action: "FDSH SSA Hub Response",
                                                                        modifier: "external Hub",
                                                                        update_reason: "Hub response",
                                                                        event_response_record_id: response.id)
      @result = ::Operations::People::BulkHubCallsForVerificationTypes.new.call(params)
    end

    it 'should return a success object' do
      expect(@result.success?).to be_truthy
    end

    it 'should return a success message' do
      expect(@result.success).to eq([[person.hbx_id, person.verification_types.ssn_type.first.type_name, "Request was sent to FedHub."]])
    end
  end

  context 'when there are multiple person records' do
    let(:person1) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:family1) { FactoryBot.create(:family, :with_primary_family_member, person: person1) }

    let(:params) { {hbx_ids: [person.hbx_id, person1.hbx_id], verification_type_names: ['Social Security Number']} }
    let(:response_payload_with_all_true) do
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

    let(:entity_response_payload_with_all_true) do
      AcaEntities::Fdsh::Ssa::H3::SSACompositeResponse.new(response_payload_with_all_true)
    end

    let(:response_payload_with_only_ssn_true) do
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
              :PersonUSCitizenIndicator => false,
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

    let(:entity_response_payload_with_only_ssn_true) do
      AcaEntities::Fdsh::Ssa::H3::SSACompositeResponse.new(response_payload_with_only_ssn_true)
    end

    context 'when there is response payload' do
      before do
        person.consumer_role.lawful_presence_determination.ssa_responses << EventResponse.new({received_at: Time.now, body: entity_response_payload_with_all_true.to_h.to_json})
        person.save!
        response = person.consumer_role.lawful_presence_determination.ssa_responses.first
        person.verification_types.ssn_type.first.add_type_history_element(action: "FDSH SSA Hub Response",
                                                                          modifier: "external Hub",
                                                                          update_reason: "Hub response",
                                                                          event_response_record_id: response.id)

        person1.consumer_role.lawful_presence_determination.ssa_responses << EventResponse.new({received_at: Time.now, body: entity_response_payload_with_only_ssn_true.to_h.to_json})
        person1.save!
        response1 = person1.consumer_role.lawful_presence_determination.ssa_responses.first
        person1.verification_types.ssn_type.first.add_type_history_element(action: "FDSH SSA Hub Response",
                                                                           modifier: "external Hub",
                                                                           update_reason: "Hub response",
                                                                           event_response_record_id: response1.id)
        @result = ::Operations::People::BulkHubCallsForVerificationTypes.new.call(params)
      end

      it 'should return a success object' do
        expect(@result.success?).to be_truthy
      end

      it 'should return a success message' do
        expect(@result.success).to match_array([[person.hbx_id, person.verification_types.ssn_type.first.type_name, "Request was sent to FedHub."], [person1.hbx_id, person1.verification_types.ssn_type.first.type_name, "not eligible for hub call"]])
      end
    end

    context 'when there are multiple requests and responses' do
      before do
        person.consumer_role.lawful_presence_determination.ssa_responses << EventResponse.new({received_at: Time.now, body: entity_response_payload_with_all_true.to_h.to_json})
        person.save!
        response = person.consumer_role.lawful_presence_determination.ssa_responses.first
        person.verification_types.ssn_type.first.add_type_history_element(action: "Hub Request",modifier: "admin", update_reason: "Hub request")
        person.verification_types.ssn_type.first.add_type_history_element(action: "FDSH SSA Hub Response",
                                                                          modifier: "external Hub",
                                                                          update_reason: "Hub response",
                                                                          event_response_record_id: response.id)
        person.verification_types.ssn_type.first.add_type_history_element(action: "Hub Request",modifier: "admin", update_reason: "Hub request")

        person1.consumer_role.lawful_presence_determination.ssa_responses << EventResponse.new({received_at: Time.now, body: entity_response_payload_with_only_ssn_true.to_h.to_json})
        person1.save!
        response1 = person1.consumer_role.lawful_presence_determination.ssa_responses.first
        person1.verification_types.ssn_type.first.add_type_history_element(action: "FDSH SSA Hub Response",
                                                                           modifier: "external Hub",
                                                                           update_reason: "Hub response",
                                                                           event_response_record_id: response1.id)
        @result = ::Operations::People::BulkHubCallsForVerificationTypes.new.call(params)
      end

      it 'should return a success object' do
        expect(@result.success?).to be_truthy
      end

      it 'should return a success message' do
        expect(@result.success).to match_array([[person.hbx_id, person.verification_types.ssn_type.first.type_name, "Request was sent to FedHub."], [person1.hbx_id, person1.verification_types.ssn_type.first.type_name, "not eligible for hub call"]])
      end
    end
  end
end