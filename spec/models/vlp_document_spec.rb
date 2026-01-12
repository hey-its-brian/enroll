require 'rails_helper'

if ExchangeTestingConfigurationHelper.individual_market_is_enabled?
  RSpec.describe VlpDocument, :type => :model do
    let(:person) {FactoryBot.create(:person, :with_consumer_role)}
    let(:person2) {FactoryBot.create(:person, :with_consumer_role)}


    describe "creates person with vlp_docs" do
      it "creates scope for uploaded docs" do
        expect(person.consumer_role.vlp_documents).to exist
      end

      it "returns number of uploaded documents" do
        person2.consumer_role.vlp_documents.first.identifier = "url"
        expect(person2.consumer_role.vlp_documents.select{|d| d.identifier.present?}.count).to eq(1)
      end
    end

    context "verification reasons" do
      if EnrollRegistry[:enroll_app].setting(:site_key).item == :me
        it "should have crm document system as verification reason" do
          expect(VlpDocument::VERIFICATION_REASONS).to include("Self-attestation")
          expect(VlpDocument::VERIFICATION_REASONS).to include("CRM document management system")
          expect(EnrollRegistry[:verification_reasons].item).to include("CRM document management system")
        end
      end
      if EnrollRegistry[:enroll_app].setting(:site_key).item == :dc
        it "should have salesforce as verification reason" do
          expect(VlpDocument::VERIFICATION_REASONS).to include("Self-Attestation")
          expect(VlpDocument::VERIFICATION_REASONS).to include("Salesforce")
          expect(EnrollRegistry[:verification_reasons].item).to include("Salesforce")
        end
      end
    end

    # Because the constants are frozen, we need to remove the model and reload the file
    # after setting the FF in order to test what happens when the feature is enabled
    context "with non applicant verification reason turned on" do
      before do
        Object.send(:remove_const, :VlpDocument) if Module.const_defined?(:VlpDocument)
        allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:non_applicant_verification_reason).and_return(true)
        load 'app/models/vlp_document.rb'
      end

      it "should have non applicant verification reason" do
        expect(VlpDocument::VERIFICATION_REASONS).to include("Non-applicant")
      end
    end

    context "with non applicant verification reason turned off" do
      before do
        Object.send(:remove_const, :VlpDocument) if Module.const_defined?(:VlpDocument)
        allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)
        load 'app/models/vlp_document.rb'
      end

      it "should not have non applicant verification reason" do
        expect(VlpDocument::VERIFICATION_REASONS).not_to include("Non-applicant")
      end
    end

    context "rejection reasons" do
      context "out of income threshold reason enabled" do
        before do
          # Because the constants are frozen, we need to remove the model and reload the file
          # after setting the FF in order to test what happens when the feature is enabled
          Object.send(:remove_const, :VlpDocument) if Module.const_defined?(:VlpDocument)
          allow(EnrollRegistry).to receive(:feature_enabled?).and_return(true)
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:out_of_income_threshold_reject_reason).and_return(true)
          load 'app/models/vlp_document.rb'
        end

        it "should include Out of Income Threshold as a rejection reason" do
          expect(VlpDocument::ALL_TYPES_REJECT_REASONS).to include("Out of Income Threshold")
        end
      end

      context "out of income threshold reason disabled" do
        before do
          Object.send(:remove_const, :VlpDocument) if Module.const_defined?(:VlpDocument)
          allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:out_of_income_threshold_reject_reason).and_return(false)
          load 'app/models/vlp_document.rb'
        end

        it "should not include Out of Income Threshold as a rejection reason" do
          expect(VlpDocument::ALL_TYPES_REJECT_REASONS).not_to include("Out of Income Threshold")
        end
      end
    end

    context "COUNTRIES_LIST" do
      it "includes correctly spelled country names" do
        expect(VlpDocument::COUNTRIES_LIST).to include("Colombia")
        expect(VlpDocument::COUNTRIES_LIST).to include("Vietnam")
      end

      it "does not include misspelled country names" do
        expect(VlpDocument::COUNTRIES_LIST).not_to include("Colombi")
        expect(VlpDocument::COUNTRIES_LIST).not_to include("Viet nam")
      end
    end
  end
end
