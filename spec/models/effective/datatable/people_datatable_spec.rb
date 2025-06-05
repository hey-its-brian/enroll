# frozen_string_literal: true

require 'rails_helper'

describe Effective::Datatables::PeopleDataTable, "with correct access permissions", dbclean: :after_each do
  let(:admin_user) { FactoryBot.create(:user, person: admin_person) }
  let(:admin_person) { FactoryBot.create(:person, :with_hbx_staff_role) }
  let(:regular_user) { FactoryBot.create(:user, person: regular_person) }
  let(:regular_person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: regular_person) }
  let(:primary_applicant) { family.primary_applicant }

  let(:enabled) { false }

  before :each do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(enabled)
  end

  subject { Effective::Datatables::PeopleDataTable.new }

  it "allows hbx staff which have the permission" do
    expect(subject.authorized?(admin_user, nil, nil, nil)).to be_truthy
  end

  it "blocks regular users" do
    expect(subject.authorized?(regular_user, nil, nil, nil)).to be_falsey
  end

  describe '#can_display_edit_dob_ssn?' do
    context 'when qhp_application feature is enabled' do
      let(:enabled) { true }

      context 'when person has families' do
        before do
          family
        end

        it 'returns disabled' do
          expect(
            subject.can_display_edit_dob_ssn?(regular_person, true)
          ).to eq('disabled')
        end
      end

      context 'when person is accociated with a family but family member is not active' do
        before do
          primary_applicant.update!(is_active: false)
        end

        it 'returns ajax' do
          expect(
            subject.can_display_edit_dob_ssn?(regular_person, true)
          ).to eq('ajax')
        end
      end

      context 'when person does not have families' do
        it 'returns ajax' do
          expect(
            subject.can_display_edit_dob_ssn?(regular_person, true)
          ).to eq('ajax')
        end
      end
    end

    context 'when qhp_application feature is disabled' do
      context 'when person is actively associated with a family' do
        before do
          family
        end

        it 'returns ajax' do
          expect(
            subject.can_display_edit_dob_ssn?(regular_person, true)
          ).to eq('ajax')
        end
      end

      context 'when person does not have families' do
        it 'returns disabled' do
          expect(
            subject.can_display_edit_dob_ssn?(regular_person, true)
          ).to eq('disabled')
        end
      end
    end
  end
end
