# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::ApplicationsController, dbclean: :after_each, type: :controller do
  include Dry::Monads[:do, :result]

  before :all do
    DatabaseCleaner.clean
  end

  context "with :filtered_application_list on" do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, first_name: "test1") }
    let(:user) { FactoryBot.create(:user, :person => person) }

    before do
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:filtered_application_list).and_return(true)
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:haven_determination).and_call_original
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:medicaid_gateway_determination).and_call_original
      Rails.application.reload_routes!
    end

    after do
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:filtered_application_list).and_call_original
      Rails.application.reload_routes!
    end

    describe 'Feature flagged endpoints', type: :request do

      describe "GET /applications" do
        let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
        let!(:application) { FactoryBot.create :financial_assistance_application, :with_applicants, family_id: family.id, aasm_state: 'determined' }

        before(:each) do
          person.consumer_role.move_identity_documents_to_verified
          sign_in(user)
        end

        it 'succeeds' do
          get '/financial_assistance/applications'
          expect(response).to render_template(:index_with_filter)
        end

        context "when the request type is invalid" do
          let(:operation_instance) { instance_double(FinancialAssistance::Operations::Applications::QueryFilteredApplications) }
          let(:failure_result) { Dry::Monads::Result::Failure.new({message: "error message"}) }

          it "should not render the index_with_filter template" do
            allow(FinancialAssistance::Operations::Applications::QueryFilteredApplications).to receive(:new).and_return(operation_instance)
            allow(operation_instance).to receive(:call).and_return(failure_result)
            get '/financial_assistance/applications', params: { format: :csv }
            expect(response.status).to eq 406
            expect(response.body).to eq "Unsupported format"
            expect(response.media_type).to eq "text/csv"
          end

          it "should not render the index_with_filter template" do
            get '/financial_assistance/applications', params: { format: :fake }
            expect(response.status).to eq 406
            expect(response.body).to eq "Unsupported format"
          end

          it "should not render the index_with_filter template" do
            get '/financial_assistance/applications', params: { format: :xml }
            expect(response.status).to eq 406
            expect(response.body).to eq "<error>Unsupported format</error>"
          end
        end
      end
    end
  end

end