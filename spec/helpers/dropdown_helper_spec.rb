# frozen_string_literal: true

RSpec.describe DropdownHelper, type: :helper do
  let(:admin_person) { FactoryBot.create(:person) }
  let(:hbx_admin) do
    FactoryBot.create(
      :hbx_staff_role,
      person: admin_person,
      permission_id: FactoryBot.create(:permission, :super_admin).id
    )
  end
  let(:admin_user) { FactoryBot.create(:user, person: hbx_admin.person) }
  let(:current_user) { admin_user }

  let(:user) { FactoryBot.create(:user, person: person) }
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

  before :each do
    allow(helper).to receive(:current_user).and_return(current_user)
    allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).and_return(false)
  end

  describe '#application_dropdowns' do
    let(:application) { FactoryBot.create(:financial_assistance_application, aasm_state: app_state, family: family) }
    let(:app_state) { 'draft' }

    context 'for update dropdown' do
      context 'when:
        - application is a draft
        - logged in user is an HBX staff member
        ' do
        it 'returns the update option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.update'))
        end
      end

      context 'when:
        - application is a draft
        - logged in user is a consumer
        ' do
        let(:current_user) { user }

        it 'returns the update option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.update'))
        end
      end

      context 'when:
        - application is a imported
        - logged in user is an HBX staff member
        ' do
        let(:app_state) { 'imported' }

        it 'returns the update option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.update'))
        end
      end

      context 'when:
        - application is a imported
        - logged in user is a consumer
        ' do
        let(:app_state) { 'imported' }
        let(:current_user) { user }

        it 'does not returns the update option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.update'))
        end
      end
    end

    context 'for copy dropdown' do
      context 'when:
        - application is a determined
        - logged in user is a consumer
        - copyable application ids includes the application id
        ' do
        let(:app_state) { 'determined' }
        let(:current_user) { user }

        it 'returns the copy option' do
          expect(
            helper.application_dropdowns(application, [application.id]).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.copy'))
        end
      end

      context 'when:
        - application is a determined
        - logged in user is an admin
        ' do
        let(:app_state) { 'determined' }

        it 'returns the copy option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.copy'))
        end
      end

      context 'when:
        - application is not determined
        - logged in user is a consumer or admin
        ' do
        let(:app_state) { 'draft' }

        it 'does not return the copy option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.copy'))
        end
      end
    end

    context 'for view_eligibility dropdown' do
      context 'when:
        - application is a determined
        - logged in user is a consumer
        ' do
        let(:app_state) { 'determined' }
        let(:current_user) { user }

        it 'returns the view eligibility option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.view_eligibility'))
        end
      end

      context 'when:
        - application is a determined
        - logged in user is an admin
        ' do
        let(:app_state) { 'determined' }

        it 'returns the view eligibility option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.view_eligibility'))
        end
      end

      context 'when:
        - application is not determined
        - logged in user is a consumer or admin
        ' do
        let(:app_state) { 'draft' }

        it 'does not return the view eligibility option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.view_eligibility'))
        end
      end
    end

    context 'for review dropdown' do
      context 'when:
        - application is a reviewable
        - logged in user is a consumer
        ' do
        let(:app_state) { 'determined' }
        let(:current_user) { user }

        it 'returns the review option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.review'))
        end
      end

      context 'when:
        - application is a reviewable
        - logged in user is an admin
        ' do
        let(:app_state) { 'determined' }

        it 'returns the review option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.review'))
        end
      end

      context 'when:
        - application is not reviewable
        - logged in user is a consumer or admin
        ' do
        let(:app_state) { 'draft' }

        it 'does not return the review option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.review'))
        end
      end

      context 'when:
        - application is initial
        - logged in user is an HBX staff member
        - QHP application feature is enabled
        ' do
        let(:app_state) { 'draft' }

        it 'returns the review option' do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)

          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.review'))
        end
      end
    end

    context 'for transfer_history' do
      context 'when:
        - application is a reviewable
        - logged in user is an HBX staff member
        - transfer history feature is enabled
        ' do
        let(:app_state) { 'determined' }
        let(:current_user) { admin_user }

        before do
          allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:transfer_history_page).and_return(true)
        end

        it 'returns the transfer history option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.transfer_history'))
        end
      end

      context 'when:
        - application is not reviewable
        - logged in user is consumer
        - transfer history feature is enabled
        ' do
        let(:app_state) { 'draft' }
        let(:current_user) { user }

        it 'does not return the transfer history option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.transfer_history'))
        end
      end

      context 'when:
        - application is a reviewable
        - logged in user is a consumer or admin
        ' do
        let(:app_state) { 'determined' }

        it 'does not return the transfer history option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.transfer_history'))
        end
      end
    end

    context 'for full_application' do
      context 'when:
        - application is a reviewable
        - logged in user is an HBX staff member
        ' do
        let(:app_state) { 'determined' }

        it 'returns the full application option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.full_application'))
        end
      end

      context 'when:
        - application is not reviewable
        - logged in user is an HBX staff member
        ' do
        let(:app_state) { 'draft' }

        it 'does not return the full application option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.full_application'))
        end
      end

      context 'when:
        - application is a reviewable
        - logged in user is a consumer
        ' do
        let(:app_state) { 'determined' }
        let(:current_user) { user }

        it 'does not return the full application option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.full_application'))
        end
      end

      context 'when:
        - application is not reviewable
        - logged in user is a consumer
        ' do
        let(:app_state) { 'draft' }
        let(:current_user) { user }

        it 'does not return the full application option' do
          expect(
            helper.application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.full_application'))
        end
      end
    end
  end

  describe '#qhp_application_dropdowns' do
    let(:application) { FactoryBot.create(:individual_market_application, current_state: app_state, family: family) }
    let(:app_state) { :initial }

    context 'for update dropdown' do
      context 'when application is initial' do
        it 'returns the update option' do
          expect(
            helper.qhp_application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.update'))
        end
      end

      context 'when application is not initial' do
        let(:app_state) { :submitted }

        it 'does not return the update option' do
          expect(
            helper.qhp_application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.update'))
        end
      end
    end

    context 'for copy dropdown' do
      context 'when application is not copyable' do
        it 'does not return the copy option' do
          expect(
            helper.qhp_application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.copy'))
        end
      end

      context 'when application is copyable' do
        it 'returns the copy option' do
          allow(helper).to receive(:do_not_allow_copy?).and_return(false)
          expect(
            helper.qhp_application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.copy'))
        end
      end
    end

    context 'for view eligibility dropdown' do
      context 'when application is determined' do
        let(:app_state) { :determined }

        it 'returns the view eligibility option' do
          expect(
            helper.qhp_application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.view_eligibility'))
        end
      end

      context 'when application is not determined' do
        let(:app_state) { :initial }

        it 'does not return the view eligibility option' do
          expect(
            helper.qhp_application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.view_eligibility'))
        end
      end
    end

    context 'for eligibility criteria dropdown' do
      context 'when:
        - application is determined
        - current user is an HBX staff member
        ' do
        let(:app_state) { :determined }

        it 'returns the eligibility criteria option' do
          expect(
            helper.qhp_application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.eligibility_criteria'))
        end
      end

      context 'when:
        - application is determined
        - current user is not an HBX staff member
        ' do
        let(:app_state) { :determined }
        let(:current_user) { user }

        it 'does not return the eligibility criteria option' do
          expect(
            helper.qhp_application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.eligibility_criteria'))
        end
      end
    end

    context 'for review dropdown' do
      context 'when:
        - application is reviewable
        - current user is a consumer
        ' do
        let(:app_state) { :determined }
        let(:current_user) { user }

        it 'returns the review option' do
          expect(
            helper.qhp_application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.review'))
        end
      end

      context 'when:
        - application is reviewable
        - current user is a Hbx staff member
        ' do
        let(:app_state) { :determined }

        it 'returns the review option' do
          expect(
            helper.qhp_application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.review'))
        end
      end

      context 'when:
        - application is not reviewable
        - current user is a consumer
        ' do
        let(:app_state) { :initial }
        let(:current_user) { user }

        it 'does not return the review option' do
          expect(
            helper.qhp_application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).not_to include(l10n('insured.sbm.applications.actions.review'))
        end
      end

      context 'when:
        - application is not reviewable
        - current user is a Hbx staff member
        ' do
        let(:app_state) { :initial }

        it 'does not return the review option' do
          expect(
            helper.qhp_application_dropdowns(application, []).collect { |dropdwn| dropdwn[:title] }
          ).to include(l10n('insured.sbm.applications.actions.review'))
        end
      end
    end
  end

  describe '#current_applications_dropdowns' do
    let(:ivl_application) { FactoryBot.create(:individual_market_application, current_state: app_state, family: family, assistance_year: year) }
    let(:faa_application) { FactoryBot.create(:financial_assistance_application, aasm_state: faa_app_state, family: family, assistance_year: year) }
    let(:app_state) { :determined }
    let(:faa_app_state) { "determined" }
    let(:draft_qhp_application) { FactoryBot.create(:individual_market_application, :initial) }
    let(:draft_faa_application) { FactoryBot.create(:financial_assistance_application, :draft) }
    let(:year) { 2025 }
    let(:alt_year) { 2024 }

    context 'when application a financial assistance application' do
      it 'returns the update option' do
        expect(helper.current_applications_dropdowns(faa_application, year, draft_faa_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.update_year', year: year))
      end

      it 'has a draft link if a draft application exists' do
        expect(helper.current_applications_dropdowns(faa_application, year, draft_faa_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.resume_draft_year', year: year))
      end

      it 'does not have a draft link if a draft application does not exist' do
        expect(helper.current_applications_dropdowns(faa_application, year, nil, alt_year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.resume_draft_year', year: year))
      end

      it 'includes the update option' do
        expect(helper.current_applications_dropdowns(faa_application, year, draft_faa_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.update_year', year: year))
      end

      it "includes the view eligibility option if the application is determined" do
        faa_application.update_attributes(aasm_state: "determined")
        expect(helper.current_applications_dropdowns(faa_application, year, draft_faa_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.view_eligibility'))
      end

      it "does not include the view eligibility option if the application is not determined" do
        expect(helper.current_applications_dropdowns(draft_faa_application, year, nil, alt_year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.view_eligibility'))
      end

      it 'includes the copy to alt year option' do
        options = helper.current_applications_dropdowns(faa_application, year, draft_faa_application, alt_year)
        expect(options.collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.copy_to_alt_year', alt_year: alt_year))
      end

      it 'does not include the copy to alt year option if the alt year is not set' do
        expect(helper.current_applications_dropdowns(faa_application, year, draft_faa_application, nil).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.copy_to_alt_year', alt_year: alt_year))
      end

      context 'when the transfer history feature is enabled' do
        before do
          allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:transfer_history_page).and_return(true)
        end

        context 'when the user is an HBX staff member' do
          let(:current_user) { admin_user }
          it 'includes the transfer history option' do
            expect(helper.current_applications_dropdowns(faa_application, year, draft_faa_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.transfer_history'))
          end
        end

        context 'when the user is not an HBX staff member' do
          let(:current_user) { user }
          it 'does not include the transfer history option' do
            expect(helper.current_applications_dropdowns(faa_application, year, draft_faa_application, alt_year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.transfer_history'))
          end
        end
      end

      context 'when the current user is an HBX staff member and qhp applications is enabled' do
        let(:current_user) { admin_user }

        it 'includes the review option when the application is determined' do
          faa_application.update_attributes(aasm_state: "determined")
          expect(helper.current_applications_dropdowns(faa_application, year, draft_faa_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end

        it 'includes the review option when the application is a draft and qhp applications is enabled' do
          faa_application.update_attributes(aasm_state: "draft")
          allow(helper).to receive(:qhp_application_feature_enabled?).and_return(true)
          expect(helper.current_applications_dropdowns(draft_faa_application, year, nil, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end
      end

      context 'when the current user is not an HBX staff member' do
        let(:current_user) { user }

        it 'does not include the review option when the application is a draft' do
          faa_application.update_attributes(aasm_state: "draft")
          expect(helper.current_applications_dropdowns(draft_faa_application, year, nil, alt_year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end

        it 'includes the review option when the application is determined' do
          faa_application.update_attributes(aasm_state: "determined")
          expect(helper.current_applications_dropdowns(faa_application, year, draft_faa_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end
      end
    end

    context 'when the application is an IVL application' do
      it 'includes the update option' do
        expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.update_year', year: year))
      end

      it 'has a draft link if a draft application exists' do
        expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.resume_draft_year', year: year))
      end

      it 'does not have a draft link if a draft application does not exist' do
        expect(helper.current_applications_dropdowns(ivl_application, year, nil, alt_year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.resume_draft_year', year: year))
      end

      it 'does not include the restore financial assistance option if the family has no financial assistance applications' do
        expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.restore_fa'))
      end

      context 'when the family has a determined financial assistance application' do
        let(:faa_application) { FactoryBot.create(:financial_assistance_application, aasm_state: "determined", family: family, assistance_year: year - 1) }

        before do
          allow(family).to receive(:latest_determined_faa_application).and_return(faa_application)
        end

        it 'includes the restore financial assistance option if the assistance year is the previous year' do
          faa_application.update_attributes(assistance_year: alt_year)
          expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.restore_fa'))
        end

        it 'includes the restore financial assistance option if the assistance year is the current year' do
          faa_application.update_attributes(assistance_year: year)
          expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.restore_fa'))
        end

        it 'does not include the restore financial assistance option if the assistance year is not the current or previous year' do
          faa_application.update_attributes(assistance_year: year + 1)
          expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.restore_fa'))
        end
      end

      it "includes the view eligibility option if the application is determined" do
        ivl_application.update_attributes(current_state: :determined)
        expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.view_eligibility'))
      end

      it "does not include the view eligibility option if the application is not determined" do
        ivl_application.update_attributes(current_state: :initial)
        expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.view_eligibility'))
      end

      it "includes the view eligibility criteria option if the application is determined" do
        ivl_application.update_attributes(current_state: :determined)
        expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.view_criteria'))
      end

      it "does not include the view eligibility criteria option if the application is not determined" do
        ivl_application.update_attributes(current_state: :initial)
        expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.view_criteria'))
      end

      context 'when the current user is not an HBX staff member' do
        let(:current_user) { user }

        it 'does not include the view eligibility criteria option' do
          expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.view_criteria'))
        end
      end

      it 'includes the copy to alt year option' do
        options = helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year)
        expect(options.collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.copy_to_alt_year', alt_year: alt_year))
      end

      it 'does not include the copy to alt year option if the alt year is not set' do
        expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, nil).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.copy_to_alt_year', alt_year: alt_year))
      end

      context 'when the application is determined and current user is an HBX staff member' do
        let(:app_state) { :determined }
        let(:current_user) { user }

        it 'includes the review option' do
          expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end
      end

      context 'when the current user is not an HBX staff member' do
        let(:current_user) { user }

        it 'does not include the review option when the application is a draft' do
          ivl_application.update_attributes(current_state: :initial)
          expect(helper.current_applications_dropdowns(draft_qhp_application, year, nil, alt_year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end

        it 'does include the review option when the application is determined' do
          ivl_application.update_attributes(current_state: :determined)
          expect(helper.current_applications_dropdowns(ivl_application, year, draft_qhp_application, alt_year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end
      end
    end
  end

  describe '#current_applications_renewal_dropdowns' do
    let(:ivl_application) { FactoryBot.create(:individual_market_application, current_state: app_state, family: family, assistance_year: year) }
    let(:faa_application) { FactoryBot.create(:financial_assistance_application, aasm_state: faa_app_state, family: family, assistance_year: year) }
    let(:app_state) { :determined }
    let(:faa_app_state) { "determined" }
    let(:year) { 2025 }

    context 'when the application is a financial assistance application' do
      it 'includes the view eligibility option' do
        expect(helper.current_applications_renewal_dropdowns(faa_application, year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.view_eligibility'))
      end

      context 'when the application is determined and current user is an HBX staff member' do
        let(:app_state) { :determined }
        let(:current_user) { user }

        it 'includes the review option' do
          expect(helper.current_applications_renewal_dropdowns(faa_application, year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end
      end

      context 'when the current user is not an HBX staff member' do
        let(:current_user) { user }

        it 'does not include the review option when the application is a draft' do
          faa_application.update_attributes(aasm_state: :initial)
          expect(helper.current_applications_renewal_dropdowns(faa_application, year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end

        it 'does include the review option when the application is determined' do
          faa_application.update_attributes(aasm_state: :determined)
          expect(helper.current_applications_renewal_dropdowns(faa_application, year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end
      end
    end

    context 'when the application is an IVL application' do
      it 'includes the view eligibility option' do
        expect(helper.current_applications_renewal_dropdowns(ivl_application, year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.view_eligibility'))
      end

      it "includes the view eligibility criteria option if the application is determined" do
        ivl_application.update_attributes(current_state: :determined)
        expect(helper.current_applications_renewal_dropdowns(ivl_application, year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.view_criteria'))
      end

      it "does not include the view eligibility criteria option if the application is not determined" do
        ivl_application.update_attributes(current_state: :initial)
        expect(helper.current_applications_renewal_dropdowns(ivl_application, year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.view_criteria'))
      end

      context 'when the current user is not an HBX staff member' do
        let(:current_user) { user }

        it 'does not include the view eligibility criteria option' do
          expect(helper.current_applications_renewal_dropdowns(ivl_application, year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.view_criteria'))
        end
      end

      context 'when current user is an HBX staff member' do
        let(:current_user) { admin_user }

        it 'includes the review option when the application is determined' do
          ivl_application.update_attributes(current_state: :determined)
          expect(helper.current_applications_renewal_dropdowns(ivl_application, year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end

        it 'includes the review option when the application is a draft when qhp applications is enabled' do
          ivl_application.update_attributes(current_state: :initial)
          allow(helper).to receive(:qhp_application_feature_enabled?).and_return(true)
          expect(helper.current_applications_renewal_dropdowns(ivl_application, year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end
      end

      context 'when the current user is not an HBX staff member' do
        let(:current_user) { user }

        it 'does not include the review option when the application is a draft' do
          ivl_application.update_attributes(current_state: :initial)
          expect(helper.current_applications_renewal_dropdowns(ivl_application, year).collect { |dropdwn| dropdwn[:title] }).not_to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end

        it 'does include the review option when the application is determined' do
          ivl_application.update_attributes(current_state: :determined)
          expect(helper.current_applications_renewal_dropdowns(ivl_application, year).collect { |dropdwn| dropdwn[:title] }).to include(l10n('insured.sbm.applications.actions.review_year', year: year))
        end
      end
    end
  end
end
