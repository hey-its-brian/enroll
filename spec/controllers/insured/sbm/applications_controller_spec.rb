# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Insured::Sbm::ApplicationsController, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role)}
  let!(:user) { FactoryBot.create(:user, :person => person) }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

  before do
    family.primary_person.consumer_role.move_identity_documents_to_verified
    sign_in user
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:bs4_consumer_flow).and_return(false)
  end

  describe 'GET #history' do
    let(:filtered_applications_value) do
      {
        applications: [qhp_application, faa_application],
        filtered_applications: [faa_application, qhp_application],
        recent_determined_hbx_id: nil
      }
    end
    let(:success_result) { Dry::Monads::Result::Success.new(filtered_applications_value) }
    let(:failure_result) { Dry::Monads::Result::Failure.new(errors: ['Some error']) }
    let(:query_operation) { instance_double(Operations::Sbm::Applications::QueryFilteredApplications) }
    let!(:qhp_application) { FactoryBot.create(:individual_market_application, :initial, :with_applicants, family_id: family.id) }
    let(:faa_application) do
      FactoryBot.create(:financial_assistance_application,
                        family_id: family.id,
                        aasm_state: 'draft',
                        assistance_year: TimeKeeper.date_of_record.year,
                        effective_date: Date.today)
    end
    let(:copyable_faa_application_ids) { [faa_application.id] }

    before do
      allow(Operations::Sbm::Applications::QueryFilteredApplications).to receive(:new).and_return(query_operation)
      allow(family).to receive(:fetch_copyable_faa_application_ids).and_return(copyable_faa_application_ids)
    end

    context 'when query operation succeeds' do
      before do
        allow(query_operation).to receive(:call).and_return(success_result)
        get :index
      end

      it 'assigns applications from the operation result' do
        expect(assigns(:applications)).to eq([qhp_application, faa_application])
      end

      it 'assigns filtered applications from the operation result' do
        expect(assigns(:filtered_applications)).to eq([faa_application, qhp_application])
      end

      it 'should not assigns recent determined HBX ID from the operation result' do
        expect(assigns(:recent_determined_hbx_id)).to eq(nil)
      end

      it 'renders the history template' do
        expect(response).to render_template('index')
      end
    end

    context 'when query operation fails' do
      before do
        allow(query_operation).to receive(:call).and_return(failure_result)
      end

      it 'returns unprocessable_entity status for json format' do
        get :index, format: :json
        expect(response.status).to eq(422)
      end

      it 'renders html format' do
        get :index
        expect(response.content_type).to include('text/html')
      end
    end

    context 'with filter parameters' do
      let(:filter_year) { '2023' }

      it 'passes filter parameters to the operation' do
        expect(query_operation).to receive(:call).with(
          {
            family_id: family.id,
            filter_year: filter_year
          }
        ).and_return(success_result)

        get :index, params: { filter: { year: filter_year } }
      end
    end

    context 'when bs4_consumer_flow feature is enabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:bs4_consumer_flow).and_return(true)
        allow(query_operation).to receive(:call).and_return(success_result)
        get :index
      end

      it 'enables bs4 layout' do
        expect(assigns(:bs4)).to be true
      end
    end

    context 'when bs4_consumer_flow feature is disabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:bs4_consumer_flow).and_return(false)
        allow(query_operation).to receive(:call).and_return(success_result)
        get :index
      end

      it 'does not enable bs4 layout' do
        expect(assigns(:bs4)).to be_nil
      end
    end
  end
end
