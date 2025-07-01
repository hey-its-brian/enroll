# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Presenters::SsnFormPresenter, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, :with_ssn) }
  let(:person_2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, :with_ssn) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_family_member) { family.primary_applicant }
  let(:faa_application) { FactoryBot.create(:financial_assistance_application, family_id: family.id) }
  let(:primary_applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      :with_ssn,
      application: faa_application,
      is_primary_applicant: true,
      family_member_id: primary_family_member.id,
      person_hbx_id: person.hbx_id
    )
  end
  let(:dependent_applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      :with_ssn,
      application: faa_application,
      is_primary_applicant: false,
      person_hbx_id: person_2.hbx_id
    )
  end
  let(:qhp_application) { FactoryBot.create(:individual_market_application, family_id: family.id) }
  let(:primary_qhp_applicant) do
    FactoryBot.build(
      :individual_market_applicant,
      application: qhp_application,
      is_primary_applicant: true,
      demographics: demographics
    )
  end
  let(:demographics) do
    {
      ssn: '123456789',
      no_ssn: false,
      dob: Date.new(1990, 1, 1)
    }
  end
  let(:ssn) { form_object.ssn }
  let(:presenter) { described_class.new(form_object, admin) }

  context 'when form object is financial assistance applicant' do
    context 'user is an admin' do
      let(:form_object) { primary_applicant }
      let(:admin) { true }

      it 'presenter form object is applicant' do
        expect(presenter.object_type).to eq('FinancialAssistance::Applicant')
      end

      it 'presenter family id is nil' do
        expect(presenter.family_id).to be_nil
      end

      it 'presenter application id is nil' do
        expect(presenter.application_id).to be_nil
      end

      it 'presenter disabled to be nil' do
        expect(presenter.disabled).to be_nil
      end

      describe 'sanitize_ssn_params' do
        context 'when qhp application is disabled' do
          before do
            allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(false)
            allow(EnrollRegistry).to receive(:feature_enabled?).with(:mask_ssn_ui_fields).and_return(true)
            presenter.sanitize_ssn_params
          end

          it 'does not set the application id' do
            expect(presenter.application_id).to be_nil
          end

          it 'does not set the applicant id' do
            expect(presenter.applicant_id).to be_nil
          end

          it 'sets the family id' do
            expect(presenter.family_id).to eq(family.id.to_s)
          end

          it 'sets the person id' do
            expect(presenter.person_id).to eq(person.id.to_s)
          end

          it 'obscures the ssn' do
            expect(presenter.obscured_ssn).to eq('●●●●●●●●●')
          end

          it 'sets the disabled to true' do
            expect(presenter.disabled).to eq(true)
          end
        end

        context 'when applicant is not primary' do
          let(:form_object) { dependent_applicant }

          before do
            allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(false)
            presenter.sanitize_ssn_params
          end

          it 'sets the disabled to false' do
            expect(presenter.disabled).to eq(false)
          end
        end

        context 'when qhp application is enabled and admin is true' do
          before do
            allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
            presenter.sanitize_ssn_params
          end

          it 'sets the disabled to false' do
            expect(presenter.disabled).to eq(false)
          end
        end
      end
    end

    context 'user is not an admin and qhp is enabled' do
      let(:form_object) { primary_applicant }
      let(:admin) { false }

      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
        presenter.sanitize_ssn_params
      end

      it 'sets the disabled to true' do
        expect(presenter.disabled).to eq(true)
      end
    end
  end

  context 'when form object is individual market demographics' do
    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:mask_ssn_ui_fields).and_return(true)
    end

    context 'user is an admin' do
      let(:form_object) { primary_qhp_applicant.demographics }
      let(:admin) { true }

      it 'presenter form object is demographics' do
        expect(presenter.object_type).to eq('IndividualMarket::Demographics')
      end

      it 'presenter family id is nil' do
        expect(presenter.family_id).to be_nil
      end

      it 'presenter application id is nil' do
        expect(presenter.application_id).to be_nil
      end

      it 'presenter disabled to be nil' do
        expect(presenter.disabled).to be_nil
      end

      describe 'sanitize_ssn_params' do
        before do
          presenter.sanitize_ssn_params
        end

        it 'does set the application id' do
          expect(presenter.application_id).to eq(qhp_application.id.to_s)
        end

        it 'does set the applicant id' do
          expect(presenter.applicant_id).to eq(primary_qhp_applicant.id.to_s)
        end

        it 'does not set the family id' do
          expect(presenter.family_id).to be_nil
        end

        it 'does not set the person id' do
          expect(presenter.person_id).to be_nil
        end

        it 'obscures the ssn' do
          expect(presenter.obscured_ssn).to eq('●●●●●●●●●')
        end

        it 'sets the disabled to false' do
          expect(presenter.disabled).to eq(false)
        end
      end
    end

    context 'user is not an admin' do
      let(:form_object) { primary_qhp_applicant.demographics }
      let(:admin) { false }

      before do
        presenter.sanitize_ssn_params
      end

      it 'sets the disabled to true' do
        expect(presenter.disabled).to eq(true)
      end
    end
  end
end