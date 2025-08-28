# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Person, type: :model, :dbclean => :after_each do
  let(:person) { FactoryBot.create(:person) }
  before do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(false)
  end

  describe '#person_addresses=' do
    let(:address_attributes) { { 'kind' => 'home', 'address_1' => '123 Main St', 'city' => 'test', 'state' => 'CA', 'zip' => '52486' } }
    let(:array_attributes) { [address_attributes] }

    context 'without an existing address' do
      it 'assigns the address attributes to the addresses association' do
        person.addresses.delete_all
        expect do
          person.person_addresses = array_attributes
        end.to change { person.addresses.size }.by(1)
        expect(person.addresses.last.kind).to eq('home')
        expect(person.addresses.last.address_1).to eq('123 Main St')
        expect(person.addresses.last.city).to eq('test')
        expect(person.addresses.last.state).to eq('CA')
        expect(person.addresses.last.zip).to eq('52486')
      end
    end

    context 'with an existing address' do
      it 'updates an existing address' do
        existing_address = person.home_address
        expect do
          person.person_addresses = array_attributes
        end.to change { person.addresses.size }.by(0)
        expect(existing_address.kind).to eq('home')
        expect(existing_address.address_1).to eq('123 Main St')
        expect(existing_address.city).to eq('test')
        expect(existing_address.state).to eq('CA')
        expect(existing_address.zip).to eq('52486')
      end
    end
  end

  describe '#person_emails=' do
    let(:email_attributes) { { 'kind' => 'home', 'address' => 'test@example.com' } }
    let(:array_attributes) { [email_attributes] }

    context 'without an existing email' do
      it 'assigns the email attributes to the emails association' do
        person.emails.delete_all
        expect do
          person.person_emails = array_attributes
        end.to change { person.emails.size }.by(1)
        expect(person.emails.last.kind).to eq('home')
        expect(person.emails.last.address).to eq('test@example.com')
      end
    end

    context 'with an existing email' do
      it 'updates an existing email' do
        existing_email = person.home_email
        expect do
          person.person_emails = array_attributes
        end.to change { person.emails.size }.by(0)
        expect(existing_email.kind).to eq('home')
        expect(existing_email.address).to eq('test@example.com')
      end
    end
  end

  describe '#person_phones=' do
    let(:phone_attributes) { { 'kind' => 'home', 'full_phone_number' => '2584567854' } }
    let(:array_attributes) { [phone_attributes] }
    context 'without an existing phone' do
      it 'assigns the phone attributes to the phones association' do
        person.phones.delete_all
        expect do
          person.person_phones = array_attributes
        end.to change { person.phones.size }.by(1)
        expect(person.phones.last.kind).to eq('home')
        expect(person.phones.last.full_phone_number).to eq('2584567854')
      end
    end

    context 'with an existing phone' do
      it 'updates an existing phone' do
        existing_phone = person.home_phone
        expect do
          person.person_phones = array_attributes
        end.to change{ person.phones.size }.by(0)
        expect(existing_phone.kind).to eq('home')
        expect(existing_phone.full_phone_number).to eq('2584567854')
      end
    end
  end

  describe '#person_create_or_update_handler' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role) }

    context 'when qhp_application_feature_enabled is true' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      end

      it 'returns early without calling Operations::FinancialAssistance::PersonCreateOrUpdateHandler' do
        expect(::Operations::FinancialAssistance::PersonCreateOrUpdateHandler).not_to receive(:new)
        person.person_create_or_update_handler
      end
    end

    context 'when qhp_application_feature_enabled is false' do
      before do
        allow(EnrollRegistry[:qhp_application].feature).to receive(:is_enabled).and_return(false)
      end

      context 'when financial_assistance feature is enabled' do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:financial_assistance).and_return(true)
        end

        it 'calls Operations::FinancialAssistance::PersonCreateOrUpdateHandler' do
          handler_instance = instance_double(::Operations::FinancialAssistance::PersonCreateOrUpdateHandler)
          expect(::Operations::FinancialAssistance::PersonCreateOrUpdateHandler).to receive(:new).and_return(handler_instance)
          expect(handler_instance).to receive(:call).with({person: person, event: :person_updated})
          person.person_create_or_update_handler
        end
      end

      context 'when financial_assistance feature is not enabled' do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:financial_assistance).and_return(false)
        end

        it 'does not call Operations::FinancialAssistance::PersonCreateOrUpdateHandler' do
          expect(::Operations::FinancialAssistance::PersonCreateOrUpdateHandler).not_to receive(:new)
          person.person_create_or_update_handler
        end
      end
    end

    context 'when an exception is raised' do
      before do
        allow(EnrollRegistry[:qhp_application].feature).to receive(:is_enabled).and_return(false)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:financial_assistance).and_return(true)
        allow(::Operations::FinancialAssistance::PersonCreateOrUpdateHandler).to receive(:new).and_raise(StandardError.new("Test error"))
        allow(Rails.logger).to receive(:error)
      end

      it 'rescues the exception and logs an error' do
        expect { person.person_create_or_update_handler }.not_to raise_error
        expect(Rails.logger).to have_received(:error)
      end
    end
  end

  describe '#add_new_verification_type' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }

    context 'Alive Status verification type' do
      before do
        person.add_new_verification_type(VerificationType::ALIVE_STATUS)
      end

      it 'returns Alive Status' do
        expect(person.reload.alive_status).to be_a(VerificationType)
        expect(person.alive_status.type_name).to eq(VerificationType::ALIVE_STATUS)
        expect(person.alive_status.validation_status).to eq('unverified')
      end
    end

    context 'American Indian Status verification type' do
      context 'verification type does not exist' do
        before do
          person.add_new_verification_type(VerificationType::AMERICAN_INDIAN_STATUS)
        end

        it 'creates the verification type with the correct default status' do
          expect(person.reload.american_indian_status).to be_a(VerificationType)
          expect(person.american_indian_status.type_name).to eq(VerificationType::AMERICAN_INDIAN_STATUS)
          expect(person.american_indian_status.validation_status).to eq('attested')
        end
      end

      context 'inactive verification type already exists' do
        before do
          person.add_new_verification_type(VerificationType::AMERICAN_INDIAN_STATUS)
          person.american_indian_status.set({ inactive: true })
        end

        it 'sets the verification type to active' do
          expect(person.american_indian_status.inactive).to be_truthy
          person.add_new_verification_type(VerificationType::AMERICAN_INDIAN_STATUS) # update the existing type
          expect(person.reload.american_indian_status.inactive).to be_falsey
        end
      end
    end
  end

  describe 'track_history' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:new_hbx_id) { HbxIdGenerator.generate_member_id }

    it 'tracks history on hbx_id' do
      person.save!
      current_hbx_id = person.hbx_id
      person.hbx_id = new_hbx_id
      person.save!
      expect(person.hbx_id.to_s).to eq(new_hbx_id.to_s)
      expect(
        person.history_tracks.where(
          action: 'update',
          original: { 'hbx_id' => current_hbx_id },
          modified: { 'hbx_id' => new_hbx_id.to_s }
        ).present?
      ).to be_truthy
    end
  end

  describe '#indian_tribe_member' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role) }

    context 'when qhp feature is not enabled' do
      context 'when citizen_status is nil' do
        before do
          person.consumer_role.lawful_presence_determination.update_attributes(citizen_status: '')
          person.tribal_id = "3123123"
          person.save!
        end

        it 'returns true' do
          p = Person.all.first
          expect(p.indian_tribe_member).to be_nil
        end
      end

      context 'when citizen_status is not nil' do
        before do
          person.consumer_role.lawful_presence_determination.update_attributes(citizen_status: 'us_citizen')
          person.tribal_id = "3123123"
          person.save!
        end

        it 'returns true' do
          p = Person.all.first
          expect(p.indian_tribe_member).to be_truthy
        end
      end
    end

    context 'when qhp feature is enabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      end

      context 'when citizen_status is nil' do
        before do
          person.consumer_role.lawful_presence_determination.update_attributes(citizen_status: '')
          person.tribal_id = "3123123"
          person.save!
        end

        it 'returns true' do
          p = Person.all.first
          expect(p.indian_tribe_member).to be_truthy
        end
      end

      context 'when citizen_status is not nil' do
        before do
          person.consumer_role.lawful_presence_determination.update_attributes(citizen_status: 'us_citizen')
          person.tribal_id = "3123123"
          person.save!
        end

        it 'returns true' do
          p = Person.all.first
          expect(p.indian_tribe_member).to be_truthy
        end
      end
    end
  end
end
