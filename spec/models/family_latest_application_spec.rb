# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family, type: :model do
  after :all do
    DatabaseCleaner.clean
  end

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

  let(:current_year) { TimeKeeper.date_of_record.year }
  let(:now) {  DateTime.now }

  let(:renewal_year) { current_year + 1 }
  let(:now_as_of_yesterday) { now - 1.day }

  let(:faa_app1_state) { 'determined' }
  let(:faa_app1_submitted_at) { now }
  let(:faa_app1_assistance_year) { current_year }

  let(:faa_app1) do
    FactoryBot.create(
      :financial_assistance_application,
      family_id: family.id,
      aasm_state: faa_app1_state,
      submitted_at: faa_app1_submitted_at,
      assistance_year: faa_app1_assistance_year
    )
  end

  let(:faa_app2_state) { 'determined' }
  let(:faa_app2_submitted_at) { now_as_of_yesterday }
  let(:faa_app2_assistance_year) { renewal_year }

  let(:faa_app2) do
    FactoryBot.create(
      :financial_assistance_application,
      created_at: now_as_of_yesterday,
      family_id: family.id,
      aasm_state: faa_app2_state,
      submitted_at: faa_app2_submitted_at,
      assistance_year: faa_app2_assistance_year
    )
  end

  let(:qhp_app1_state) { :determined }
  let(:qhp_app1_submitted_at) { now + 1.hour }
  let(:qhp_app1_assistance_year) { current_year }

  let(:qhp_app1) do
    FactoryBot.create(
      :individual_market_application,
      family: family,
      current_state: qhp_app1_state,
      submitted_at: qhp_app1_submitted_at,
      assistance_year: qhp_app1_assistance_year
    )
  end

  let(:qhp_app2_state) { :determined }
  let(:qhp_app2_submitted_at) { now_as_of_yesterday - 1.hour }
  let(:qhp_app2_assistance_year) { renewal_year }

  let(:qhp_app2) do
    FactoryBot.create(
      :individual_market_application,
      created_at: qhp_app2_submitted_at,
      family: family,
      current_state: qhp_app2_state,
      submitted_at: qhp_app2_submitted_at,
      assistance_year: qhp_app2_assistance_year
    )
  end

  describe '#assign_latest_application_gid' do
    context 'when:
      - there are no applications
      ' do

      it 'returns nil' do
        family.assign_latest_application_gid
        expect(family.latest_application_gid).to be_nil
      end
    end

    context 'when:
      - there are FAA applications only
    ' do

      before do
        faa_app1
        faa_app2
      end

      it 'returns the latest FAA application' do
        family.assign_latest_application_gid
        expect(family.latest_application_gid).to eq(faa_app2.to_global_id.uri.to_s)
      end
    end

    context 'when:
      - there are QHP applications only
    ' do

      before do
        qhp_app1
        qhp_app2
      end

      it 'returns the latest QHP application' do
        family.assign_latest_application_gid
        expect(family.latest_application_gid).to eq(qhp_app2.to_global_id.uri.to_s)
      end
    end

    context 'when:
      - there are both FAA and QHP applications
    ' do

      before do
        faa_app1
        faa_app2
        qhp_app1
        qhp_app2
      end

      it 'returns the latest FAA application' do
        family.assign_latest_application_gid
        expect(family.latest_application_gid).to eq(faa_app2.to_global_id.uri.to_s)
      end
    end

    context 'when:
      - there is a FAA application with renewal year that is submitted yesterday
      - there is a QHP application with current year that is submitted today
    ' do

      before do
        faa_app2
        qhp_app1
      end

      it 'returns the latest FAA application' do
        family.assign_latest_application_gid
        expect(family.latest_application_gid).to eq(faa_app2.to_global_id.uri.to_s)
      end
    end
  end

  describe '#latest_application' do
    context 'when latest_application_gid is qhp application' do
      it 'returns the qhp application' do
        family.latest_application_gid = qhp_app2.to_global_id.uri.to_s
        expect(family.latest_application).to eq(qhp_app2)
      end
    end

    context 'when latest_application_gid is faa application' do
      it 'returns the faa application' do
        family.latest_application_gid = faa_app2.to_global_id.uri.to_s
        expect(family.latest_application).to eq(faa_app2)
      end
    end

    context 'when latest_application_gid is nil' do
      it 'returns nil' do
        expect(family.latest_application).to be_nil
      end
    end
  end

  describe '#latest_application_gid' do
    context 'when latest_application_gid is qhp application' do
      it 'returns the qhp application gid' do
        family.latest_application_gid = qhp_app2.to_global_id.uri.to_s
        family.save!
        family.reload
        expect(family.latest_application_type).to eq('qhp')
      end
    end

    context 'when latest_application_gid is faa application' do
      it 'returns the faa application gid' do
        family.latest_application_gid = faa_app2.to_global_id.uri.to_s
        family.save!
        family.reload
        expect(family.latest_application_type).to eq('faa')
      end
    end

    context 'when latest_application_gid is nil' do
      it 'returns nil' do
        expect(family.latest_application_type).to be_nil
      end
    end

    context 'when latest_application_gid is not a valid gid' do
      it 'returns nil' do
        family.latest_application_gid = 'invalid_gid'
        family.save!
        family.reload
        expect(family.latest_application_type).to be_nil
      end
    end

    context 'when latest_application_gid is not an application gid' do
      it 'returns nil' do
        family.latest_application_gid = person.to_global_id.uri.to_s
        family.save!
        family.reload
        expect(family.latest_application_type).to be_nil
      end
    end
  end
end
