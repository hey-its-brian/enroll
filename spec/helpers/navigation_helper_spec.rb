# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NavigationHelper, :type => :helper, dbclean: :after_each do

  context 'application_year_selection page' do
    let(:action_name)     {"application_year_selection"}
    let(:controller_name) {'consumer_roles'}

    describe 'tell_us_about_yourself_active?' do
      it "should return true while on application year selection page" do
        expect(tell_us_about_yourself_active?).to eq(true)
      end
    end

    describe 'account_registration_active?' do
      it "should return false while on application year selection page" do
        expect(account_registration_active?).to eq(false)
      end
    end

    describe 'tell_us_about_yourself_current_step?' do
      it "should return true while on application year selection page" do
        expect(tell_us_about_yourself_current_step?).to eq(true)
      end
    end

    describe 'family_members_index_active?' do
      it "should return nil while on application year selection page" do
        expect(family_members_index_active?).to eq(nil)
      end
    end

    describe 'family_members_index_current_step?' do
      it "should return nil while on application year selection page" do
        expect(family_members_index_current_step?).to eq(nil)
      end
    end
  end

  describe 'show_account_button functionality' do

    before do
      allow(helper).to receive(:l10n).and_return('test_translation')
    end

    describe '#plan_shopping_nav_options' do
      let(:step) { 1 }
      let(:nav_options) { [] }

      it 'sets show_account_button to true' do
        result = plan_shopping_nav_options(step, nav_options)
        expect(result[:show_account_button]).to be true
      end

      it 'includes all expected navigation keys' do
        result = plan_shopping_nav_options(step, nav_options)
        expect(result.keys).to include(:nav_options, :links, :step, :title, :back_to_account_flag, :show_account_button, :show_help_button)
      end
    end

    describe '#new_application_nav_options' do
      let(:step) { 1 }

      it 'sets show_account_button to true' do
        result = new_application_nav_options(step)
        expect(result[:show_account_button]).to be true
      end

      it 'sets back_to_account_flag to true' do
        result = new_application_nav_options(step)
        expect(result[:back_to_account_flag]).to be true
      end
    end

    describe '#sign_up_nav_options' do
      let(:step) { 1 }

      context 'with default parameters' do
        it 'sets show_account_button to false' do
          result = sign_up_nav_options(step)
          expect(result[:show_account_button]).to be false
        end

        it 'sets back_to_account_flag to false' do
          result = sign_up_nav_options(step)
          expect(result[:back_to_account_flag]).to be false
        end
      end

      context 'with show_help_button option' do
        it 'respects show_help_button parameter when true' do
          result = sign_up_nav_options(step, show_help_button: true)
          expect(result[:show_help_button]).to be true
        end

        it 'shows help button on step 2 by default' do
          result = sign_up_nav_options(2)
          expect(result[:show_help_button]).to be true
        end
      end

      context 'with dont_show_exit_button option' do
        it 'hides exit button when dont_show_exit_button is true' do
          result = sign_up_nav_options(step, dont_show_exit_button: true)
          expect(result[:show_exit_button]).to be_nil
        end

        it 'shows exit button by default' do
          result = sign_up_nav_options(step)
          expect(result[:show_exit_button]).to be true
        end
      end
    end

    describe '#individual_market_nav_options' do
      let(:application) { FactoryBot.create(:individual_market_application, :with_primary) }
      let(:step) { 1 }

      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:back_to_account_all_shop).and_return(true)
      end

      context 'when back_to_account_all_shop feature is enabled' do
        context 'with show_account_button parameter true (default)' do
          it 'sets show_account_button to true' do
            result = individual_market_nav_options(step, application)
            expect(result[:show_account_button]).to be true
          end
        end

        context 'with show_account_button parameter false' do
          it 'sets show_account_button to false' do
            result = individual_market_nav_options(step, application, show_account_button: false)
            expect(result[:show_account_button]).to be false
          end
        end
      end

      context 'when back_to_account_all_shop feature is disabled' do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:back_to_account_all_shop).and_return(false)
        end

        it 'sets show_account_button to false regardless of parameter' do
          result = individual_market_nav_options(step, application, show_account_button: true)
          expect(result[:show_account_button]).to be false
        end
      end

      it 'includes all expected navigation properties' do
        result = individual_market_nav_options(step, application)
        expected_keys = [:nav_options, :step, :title, :show_help_button, :show_exit_button,
                         :show_previous_button, :show_account_button, :back_to_account_flag]
        expect(result.keys).to include(*expected_keys)
      end

      it 'sets other expected boolean flags correctly' do
        result = individual_market_nav_options(step, application)
        expect(result[:show_help_button]).to be true
        expect(result[:show_exit_button]).to be true
        expect(result[:show_previous_button]).to be false
        expect(result[:back_to_account_flag]).to be true
      end

      it 'includes navigation options with expected structure' do
        result = individual_market_nav_options(step, application)
        expect(result[:nav_options]).to be_an(Array)
        expect(result[:nav_options].first).to include(:step, :page_key, :link, :label)
      end
    end

    describe 'feature flag integration' do
      let(:application) { FactoryBot.create(:individual_market_application, :with_primary) }

      it 'responds to EnrollRegistry feature flags' do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:back_to_account_all_shop).and_return(false)

        result = individual_market_nav_options(1, application)
        expect(result[:show_account_button]).to be false

        allow(EnrollRegistry).to receive(:feature_enabled?).with(:back_to_account_all_shop).and_return(true)

        result = individual_market_nav_options(1, application)
        expect(result[:show_account_button]).to be true
      end
    end
  end

  describe '#verification_navigation' do
    let(:person_id) { '123abc' }
    let(:member) { double('member', person_id: person_id) }
    let(:detail_params) { { id: '456def' } }
    let(:evidence) { double('evidence', detail_params: detail_params, evidence_group: 'ridp') }

    before do
      allow(helper).to receive(:action_name).and_return(action_name)
    end

    context 'when action_name is verification' do
      let(:action_name) { 'verification' }

      it 'returns the correct navigation structure with one breadcrumb' do
        result = helper.verification_navigation(member, evidence, display_previous_evidences: false)

        expect(result[:breadcrumbs].length).to eq(1)
        expect(result[:breadcrumbs][0][:title]).to eq('Verifications')
      end
    end

    context 'when action_name is verification_individual' do
      let(:action_name) { 'verification_individual' }

      it 'returns the correct navigation structure with two breadcrumbs' do
        result = helper.verification_navigation(member, evidence, display_previous_evidences: false)

        expect(result[:breadcrumbs].length).to eq(2)
        expect(result[:breadcrumbs][1][:title]).to eq('Individual')
        expect(result[:previous_step][:title]).to eq('Verifications')
      end
    end

    context 'when action_name is verification_detail' do
      let(:action_name) { 'verification_detail' }

      it 'returns the correct navigation structure with three breadcrumbs' do
        result = helper.verification_navigation(member, evidence, display_previous_evidences: false)

        expect(result[:breadcrumbs].length).to eq(3)
        expect(result[:breadcrumbs][2][:title]).to eq('Verification Detail')
        expect(result[:previous_step][:title]).to eq('Individual')
      end
    end

    context 'when action_name is verification_history' do
      let(:action_name) { 'verification_history' }

      it 'adds verification_history step to the navigation' do
        result = helper.verification_navigation(member, evidence, display_previous_evidences: false)

        expect(result[:breadcrumbs].length).to eq(4)
        expect(result[:breadcrumbs][3][:title]).to eq('Verification History')
        expect(result[:previous_step][:title]).to eq('Verification Detail')
      end
    end

    context 'when action_name is index' do
      let(:action_name) { 'index' }

      context 'when qhp_application_feature is enabled' do
        before do
          allow(helper).to receive(:qhp_application_feature_enabled?).and_return(true)
        end

        it 'adds index step to the navigation' do
          result = helper.verification_navigation(member, evidence, display_previous_evidences: false)

          expect(result[:breadcrumbs].length).to eq(4)
          expect(result[:breadcrumbs][3][:title]).to eq('Upload History')
          expect(result[:breadcrumbs][3][:link]).to eq('#')
          expect(result[:previous_step][:title]).to eq('Verification Detail')
        end
      end

      context 'when qhp_application_feature is disabled' do
        before do
          allow(helper).to receive(:qhp_application_feature_enabled?).and_return(false)
        end

        it 'does not add index step to the navigation' do
          result = helper.verification_navigation(member, evidence, display_previous_evidences: false)

          expect(result[:breadcrumbs].length).to eq(3)
          expect(result[:breadcrumbs][2][:title]).to eq('Verification Detail')
        end
      end
    end
  end
end
