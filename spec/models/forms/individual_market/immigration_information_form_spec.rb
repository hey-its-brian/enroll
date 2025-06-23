# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Forms::IndividualMarket::ImmigrationInformationForm, type: :model, dbclean: :after_each do

  let(:params) do
    {
      subject: "I-551 (Permanent Resident Card)",
      alien_number: "987654321",
      card_number: "ahp8901236283",
      expiration_date: "2025-07-12",
      immigration_doc_statuses: ["Member of a Federally Recognized Indian Tribe", "Cuban/Haitian Entrant"]
    }
  end

  context 'with valid params' do

    before do
      @form = described_class.new(params)
    end

    it 'should build the form' do
      expect(@form).to be_truthy
    end

    it 'should be valid' do
      expect(@form).to be_valid
    end

    it 'should have no errors' do
      expect(@form.errors.full_messages).to be_empty
    end

  end

  it 'should fail when the subject is invalid' do
    params[:subject] = "Invalid Document"
    form = described_class.new(params)
    expect(form.valid?).to be_falsey
    expect(form.errors.full_messages.first).to include("Subject must be one of ")
  end

  it 'should sanitize the subject' do
    params[:subject] = "   I-551 (Permanent Resident Card)   "
    form = described_class.new(params)
    expect(form.subject).to eq("I-551 (Permanent Resident Card)")
  end

  it 'should remove the prompt from the subject' do
    params[:subject] = "Select Document Type"
    form = described_class.new(params)
    expect(form.subject).to be_nil
  end

  it 'should remove blank items from the immigration_doc_statuses array' do
    params[:immigration_doc_statuses] = ["", "Member of a Federally Recognized Indian Tribe", "Cuban/Haitian Entrant"]
    form = described_class.new(params)
    expect(form.immigration_doc_statuses).to eq(["Member of a Federally Recognized Indian Tribe", "Cuban/Haitian Entrant"])
  end
end