# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::DataFixes::CreateSsaVerificationType, dbclean: :after_each do
  let!(:person) { FactoryBot.create(:person, :with_consumer_role, :male, first_name: 'john', last_name: 'adams', dob: 40.years.ago, ssn: '472743442') }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person)}
  let(:params) { {person_hbx_id: person.hbx_id} }

  describe "invalid params" do
    it "should fail" do
      person.verification_types.ssn_type.delete_all
      person.unset(:encrypted_ssn)
      result = described_class.new.call(params)
      expect(result).to be_failure
      expect(result.failure).to eq("Person SSN is not present to create SSA verification type")
    end
  end

  describe "valid params" do
    it 'should not triggers callbacks when creating verification type' do
      person.verification_types.ssn_type.delete_all

      person_finder = instance_double(::Operations::People::Find)
      allow(::Operations::People::Find).to receive(:new).and_return(person_finder)
      allow(person_finder).to receive(:call).and_return(Dry::Monads::Success(person))

      expect(person).not_to receive(:person_create_or_update_handler)
      expect(person).not_to receive(:generate_person_saved_event)
      expect(person).not_to receive(:publish_updated_event)
      expect(person.verification_types.ssn_type.count).to eq(0)
      result = described_class.new.call(params)
      expect(result).to be_success
      expect(result.success).to eq("Successfully created verification type")
      person.reload
      expect(person.verification_types.ssn_type.count).to eq(1)
      expect(person.verification_types.ssn_type.first.validation_status).to eq("verified")
      type_history_elements = person.verification_types.ssn_type.first.type_history_elements
      expect(type_history_elements.count).to eq(1)
      expect(type_history_elements.first.action).to eq("Data Migration - Evidence Records")
      expect(type_history_elements.first.modifier).to eq("Script")
      expect(type_history_elements.first.from_validation_status).to eq("unverified")
      expect(type_history_elements.first.to_validation_status).to eq("verified")
    end
  end
end