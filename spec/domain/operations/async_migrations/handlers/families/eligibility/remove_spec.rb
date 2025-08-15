# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Handlers::Families::Eligibility::Remove, dbclean: :after_each do

  let(:subject) { described_class.new }
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:family_member) { family.primary_applicant }

  let!(:determination) do
    det = FactoryBot.build(:eligibilities_determination, effective_date: Date.today)
    subject = FactoryBot.build(
      :eligibilities_subject,
      person_id: person.id.to_s,
      gid: family_member.to_global_id
    )

    aptc_state = FactoryBot.build(
      :eligibilities_eligibility_state,
      eligibility_item_key: 'aptc_csr_credit'
    )

    aptc_grant = FactoryBot.build(
      :eligibilities_grant,
      key: 'AdvancePremiumAdjustmentGrant',
      member_ids: [family_member.id.to_s]
    )

    aptc_state.grants << aptc_grant
    subject.eligibility_states << aptc_state

    market_state = FactoryBot.build(
      :eligibilities_eligibility_state,
      eligibility_item_key: 'aca_individual_market_eligibility'
    )

    qhp_grant = FactoryBot.build(
      :eligibilities_grant,
      key: 'QhpGrant',
      member_ids: [family_member.id.to_s]
    )

    market_state.grants << qhp_grant
    subject.eligibility_states << market_state

    det.subjects << subject

    family.eligibility_determination = det
    family.save!
    det
  end

  context 'when params are valid' do
    let(:params) { { document_id: family.id } }

    it 'returns a success monad' do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      expect(family.eligibility_determination).not_to be_nil
      result = subject.call(params)
      expect(result).to be_a(Dry::Monads::Result::Success)
      family.reload
      expect(family.eligibility_determination).to be_nil
    end
  end

  context 'when params are invalid' do
    it 'returns a failure monad when params is not a hash' do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      result = subject.call([])
      expect(result).to be_a(Dry::Monads::Result::Failure)
      expect(result.failure).to eq('Params must be a hash')
    end

    it 'returns a failure monad when document_id is invalid' do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      result = subject.call(document_id: 'invalid')
      expect(result).to be_a(Dry::Monads::Result::Failure)
      expect(result.failure).to eq('Document id must be of valid BSON::ObjectId format')
    end

    it 'returns a failure monad when qhp_application_feature is not enabled' do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(false)
      result = subject.call(document_id: family.id)
      expect(result).to be_a(Dry::Monads::Result::Failure)
      expect(result.failure).to eq('qhp_application_feature flag is not enabled')
    end
  end

end