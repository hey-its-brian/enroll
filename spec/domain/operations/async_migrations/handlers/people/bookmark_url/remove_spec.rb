# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Handlers::People::BookmarkURL::Remove, dbclean: :after_each do
  let(:subject) { described_class.new }
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:user) { FactoryBot.create(:user, :person => person) }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

  context 'when person has user' do
    let(:params) { { document_id: person.id } }

    context 'and is RIDP verified' do
      before do
        user
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
        person.consumer_role.update(identity_validation: 'valid', application_validation: 'valid', bookmark_url: 'some_url', admin_bookmark_url: 'some_admin_url')
        person.user.update(identity_final_decision_code: 'acc')
      end

      it 'returns a success monad' do
        expect(person.consumer_role.bookmark_url).to be_present
        expect(person.consumer_role.admin_bookmark_url).to be_present
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        person.reload
        expect(person.consumer_role.bookmark_url).to be_nil
        expect(person.consumer_role.admin_bookmark_url).to be_nil
      end
    end

    context 'but is not RIDP verified' do
      before do
        user
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
        person.consumer_role.update(identity_validation: 'valid', application_validation: 'valid', bookmark_url: 'some_url', admin_bookmark_url: 'some_admin_url')
        person.user.update(identity_final_decision_code: nil)
      end

      it 'returns a Success monad' do
        expect(person.consumer_role.bookmark_url).to be_present
        expect(person.consumer_role.admin_bookmark_url).to be_present
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.value!).to eq("User with person hbx_id: #{person.hbx_id} is not identity verified")
        person.reload
        expect(person.consumer_role.bookmark_url).to be_present
        expect(person.consumer_role.admin_bookmark_url).to be_present
      end
    end
  end

  context 'when person does not have user' do
    let(:params) { { document_id: person.id } }

    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      person.consumer_role.update(identity_validation: 'valid', application_validation: 'valid', bookmark_url: 'some_url', admin_bookmark_url: 'some_admin_url')
    end

    it 'returns a Success monad' do
      expect(person.consumer_role.bookmark_url).to be_present
      expect(person.consumer_role.admin_bookmark_url).to be_present
      result = subject.call(params)
      expect(result).to be_a(Dry::Monads::Result::Success)
      expect(result.value!).to eq("Person hbx_id: #{person.hbx_id} is not associated with a user")
      person.reload
      expect(person.consumer_role.bookmark_url).to be_present
      expect(person.consumer_role.admin_bookmark_url).to be_present
    end
  end

  context 'when person is not RIDP verified' do
    let(:params) { { document_id: person.id } }

    before do
      user
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      person.consumer_role.update(identity_validation: 'outstanding', application_validation: 'outstanding', bookmark_url: 'some_url', admin_bookmark_url: 'some_admin_url')
      person.user.update(identity_final_decision_code: 'acc')
    end

    it 'returns a Success monad' do
      expect(person.consumer_role.bookmark_url).to be_present
      expect(person.consumer_role.admin_bookmark_url).to be_present
      result = subject.call(params)
      expect(result).to be_a(Dry::Monads::Result::Success)
      expect(result.value!).to eq("Person hbx_id: #{person.hbx_id} is not RIDP verified")
      person.reload
      expect(person.consumer_role.bookmark_url).to be_present
      expect(person.consumer_role.admin_bookmark_url).to be_present
    end
  end

  context 'when person is not RIDP verified' do
    let(:new_person) { FactoryBot.create(:person) }
    let(:params) { { document_id: new_person.id } }

    before do
      user
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
    end

    it 'returns a Success monad' do
      result = subject.call(params)
      expect(result).to be_a(Dry::Monads::Result::Success)
      expect(result.value!).to eq("Person hbx_id: #{new_person.hbx_id} does not have a consumer role")
    end
  end
end
