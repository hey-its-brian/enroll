# frozen_string_literal: true

require 'rails_helper'

if ExchangeTestingConfigurationHelper.individual_market_is_enabled?
  RSpec.describe FinancialAssistance::IncomesController, dbclean: :after_each, type: :controller do

    before :all do
      DatabaseCleaner.clean
    end

    routes { FinancialAssistance::Engine.routes }

    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:user) { FactoryBot.create(:user, person: person) }
    let(:consumer_role) { person.consumer_role }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:primary_family_member) { family.primary_family_member }
    let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: "draft") }
    let(:primary_applicant) do
      FactoryBot.create(
        :financial_assistance_applicant,
        application: application,
        family_member_id: primary_family_member.id,
        person_hbx_id: user.person.hbx_id
      )
    end

    let(:applicant_income) do
      income = FactoryBot.build(:financial_assistance_income)
      primary_applicant.incomes << income
      income
    end

    let(:permission) { FactoryBot.create(:permission, :developer) }
    let(:developer_person) { FactoryBot.create(:person, :with_hbx_staff_role) }
    let(:user_with_developer_role) { FactoryBot.create(:user, person: developer_person) }

    before do
      developer_person.hbx_staff_role.update_attributes(permission_id: permission.id, subrole: permission.name)
      sign_in(user_with_developer_role)
      session[:person_id] = person.id
    end

    describe '#index' do
      let(:params) { { application_id: application.id, applicant_id: primary_applicant.id } }

      context 'logged in user has developer role' do
        context 'when application is not reviewable' do
          it 'denies access and redirects to a different path' do
            applicant_income
            get :index, params: params
            expect(flash[:error]).to eq(
              'Access not allowed for financial_assistance/applicant_policy.index?, (Pundit policy)'
            )
          end
        end

        context 'when application is reviewable and qhp feature is enabled' do
          let(:reviewable_application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: "submitted") }
          let(:reviewable_applicant) do
            FactoryBot.create(
              :financial_assistance_applicant,
              application: reviewable_application,
              family_member_id: primary_family_member.id,
              person_hbx_id: user.person.hbx_id
            )
          end
          let(:reviewable_params) { { application_id: reviewable_application.id, applicant_id: reviewable_applicant.id } }

          before do
            allow_any_instance_of(FinancialAssistance::IncomesController).to receive(:qhp_application_feature_enabled?).and_return(true)
          end

          it 'redirects back before authorization check' do
            get :index, params: reviewable_params
            expect(response).to redirect_to('/insured/sbm/applications')
            expect(flash[:error]).to be_nil
          end
        end

        context 'when application is reviewable but qhp feature is disabled' do
          let(:reviewable_application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: "submitted") }
          let(:reviewable_applicant) do
            FactoryBot.create(
              :financial_assistance_applicant,
              application: reviewable_application,
              family_member_id: primary_family_member.id,
              person_hbx_id: user.person.hbx_id
            )
          end
          let(:reviewable_params) { { application_id: reviewable_application.id, applicant_id: reviewable_applicant.id } }

          before do
            allow_any_instance_of(FinancialAssistance::IncomesController).to receive(:qhp_application_feature_enabled?).and_return(false)
          end

          it 'proceeds to authorization and denies access' do
            get :index, params: reviewable_params
            expect(flash[:error]).to eq(
              'Access not allowed for financial_assistance/applicant_policy.index?, (Pundit policy)'
            )
          end
        end
      end
    end

    describe '#other' do
      let(:params) { { application_id: application.id, applicant_id: primary_applicant.id } }

      context 'logged in user has developer role' do
        it 'denies access and redirects to a different path' do
          get :other, params: params
          expect(flash[:error]).to eq(
            'Access not allowed for financial_assistance/applicant_policy.other?, (Pundit policy)'
          )
        end
      end
    end

    describe '#new' do
      let(:params) { { application_id: application.id, applicant_id: primary_applicant.id } }

      context 'logged in user has developer role' do
        it 'denies access and redirects to a different path' do
          get :new, params: params
          expect(flash[:error]).to eq(
            'Access not allowed for financial_assistance/applicant_policy.new?, (Pundit policy)'
          )
        end
      end
    end

    describe '#edit' do
      let(:params) do
        {
          application_id: application.id,
          applicant_id: primary_applicant.id,
          id: applicant_income.id
        }
      end

      context 'logged in user has developer role' do
        it 'denies access and redirects to a different path' do
          get :edit, params: params
          expect(flash[:error]).to eq(
            'Access not allowed for financial_assistance/income_policy.edit?, (Pundit policy)'
          )
        end
      end
    end

    describe '#step' do
      let(:params) do
        {
          application_id: application.id,
          applicant_id: primary_applicant.id,
          id: applicant_income.id
        }
      end

      context 'logged in user has developer role' do
        it 'denies access and redirects to a different path' do
          get :step, params: params
          expect(flash[:error]).to eq(
            'Access not allowed for financial_assistance/income_policy.step?, (Pundit policy)'
          )
        end
      end
    end

    describe '#create' do
      let(:params) { { application_id: application.id, applicant_id: primary_applicant.id } }

      context 'logged in user has developer role' do
        it 'denies access and redirects to a different path' do
          post :create, params: params
          expect(flash[:error]).to eq(
            'Access not allowed for financial_assistance/applicant_policy.create?, (Pundit policy)'
          )
        end
      end
    end

    describe '#update' do
      let(:params) do
        {
          application_id: application.id,
          applicant_id: primary_applicant.id,
          id: applicant_income.id
        }
      end

      context 'logged in user has developer role' do
        it 'denies access and redirects to a different path' do
          post :update, params: params
          expect(flash[:error]).to eq(
            'Access not allowed for financial_assistance/income_policy.update?, (Pundit policy)'
          )
        end
      end
    end

    describe '#destroy' do
      let(:params) do
        {
          application_id: application.id,
          applicant_id: primary_applicant.id,
          id: applicant_income.id
        }
      end

      context 'logged in user has developer role' do
        it 'denies access and redirects to a different path' do
          post :destroy, params: params
          expect(flash[:error]).to eq(
            'Access not allowed for financial_assistance/applicant_policy.destroy?, (Pundit policy)'
          )
        end
      end
    end
  end
end
