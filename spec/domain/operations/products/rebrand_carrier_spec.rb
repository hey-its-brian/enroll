# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::Products::RebrandCarrier, dbclean: :after_each do
  subject { described_class.new }

  describe 'invalid params' do
    let(:params) { {} }

    it 'returns failure when old_name is missing' do
      result = subject.call(params)
      expect(result.failure?).to eq true
      expect(result.failure).to eq "Missing old name"
    end

    it 'returns failure when new_name is missing' do
      params[:old_name] = "Old Carrier Name"
      result = subject.call(params)
      expect(result.failure?).to eq true
      expect(result.failure).to eq "Missing new name"
    end
  end

  describe 'valid params' do
    let(:old_name) { "Taro Health" }
    let(:new_name) { "Mending Health" }

    # Create issuer profiles, which will create their own ExemptOrganizations
    let!(:issuer_profile1) do
      FactoryBot.create(:benefit_sponsors_organizations_issuer_profile, :with_exempt_organization, legal_name: old_name)
    end

    let!(:issuer_profile2) do
      FactoryBot.create(:benefit_sponsors_organizations_issuer_profile, :with_exempt_organization, legal_name: old_name)
    end

    let!(:issuer_profile3) do
      FactoryBot.create(:benefit_sponsors_organizations_issuer_profile, :with_exempt_organization, legal_name: "Other Carrier")
    end

    let(:organization1) { issuer_profile1.organization }
    let(:organization2) { issuer_profile2.organization }
    let(:organization3) { issuer_profile3.organization }

    let(:params) { { old_name: old_name, new_name: new_name } }

    before do
      @result = subject.call(params)
    end

    it 'returns success with correct message' do
      expect(@result.success?).to eq true
      expect(@result.success).to eq "Updated organization from '#{old_name}' to '#{new_name}'"
    end

    it 'updates the legal name of organizations matching old_name' do
      expect(organization1.reload.legal_name).to eq new_name
      expect(organization2.reload.legal_name).to eq new_name
    end

    it 'does not update organizations with a different legal name' do
      expect(organization3.reload.legal_name).to eq "Other Carrier"
    end
  end

  describe 'no organizations found' do
    let(:params) { { old_name: "Nonexistent Carrier", new_name: "New Carrier Name" } }

    it 'returns failure when no organizations match' do
      result = subject.call(params)
      expect(result.failure?).to eq true
      expect(result.failure).to eq "No organizations found with legal name: Nonexistent Carrier"
    end
  end
end
