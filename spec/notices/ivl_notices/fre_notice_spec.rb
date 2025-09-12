# frozen_string_literal: true

describe ::Notices::IvlNotices::FreNotice, dbclean: :after_each do

  describe 'trigger_notices mode' do
    let(:params) do
      { mode: 'trigger_notices',
        effective_on: TimeKeeper.date_of_record.next_year.beginning_of_year,
        created_on: Date.new(TimeKeeper.date_of_record.year, 11, 1) }
    end

    context "when multiple people present" do
      let(:person)       { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
      let(:family)       { FactoryBot.create(:family, :with_primary_family_member, person: person) }
      let!(:enrollment) do
        FactoryBot.create(
          :hbx_enrollment,
          household: family.active_household,
          effective_on: TimeKeeper.date_of_record.next_year.beginning_of_year,
          family: family,
          kind: "individual",
          aasm_state: 'auto_renewing'
        )
      end

      let(:person_two)       { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
      let(:family_two)       { FactoryBot.create(:family, :with_primary_family_member, person: person_two) }
      let!(:enrollment_two) do
        FactoryBot.create(
          :hbx_enrollment,
          household: family_two.active_household,
          effective_on: TimeKeeper.date_of_record.next_year.beginning_of_year,
          family: family_two,
          kind: "individual",
          aasm_state: 'auto_renewing'
        )
      end

      let!(:message) do
        message = person.inbox.messages.create(
          subject: "Your Plan Enrollment for #{enrollment.effective_on.year}"
        )
        message.set(created_at: Date.new(TimeKeeper.date_of_record.year, 11, 2).end_of_day)
        message
      end

      it "should trigger fre notice for family that did not receive notice already" do
        expect(subject).not_to receive(:event).with('events.families.notices.fre_notice_generation.requested', attributes: { index: 0, family_id: family.id.to_s })
        expect(subject).to receive(:event).with('events.families.notices.fre_notice_generation.requested', attributes: { index: 1, family_id: family_two.id.to_s })

        subject.call(params)
      end

      context "when primary person is not present" do
        before do
          family.primary_applicant.set(is_primary_applicant: nil)
        end

        it "should not trigger fre notice for family that did not receive notice already" do
          expect(subject).not_to receive(:event).with('events.families.notices.fre_notice_generation.requested', attributes: { index: 0, family_id: family.id.to_s })
          expect(subject).to receive(:event).with('events.families.notices.fre_notice_generation.requested', attributes: { index: 1, family_id: family_two.id.to_s })

          subject.call(params)
        end
      end
    end
  end

  describe 'notices_report mode' do
    let(:params) do
      { mode: 'notices_report',
        effective_on: TimeKeeper.date_of_record.next_year.beginning_of_year,
        created_on: Date.new(TimeKeeper.date_of_record.year, 11, 1) }
    end
    let(:file_pattern) { "#{Rails.root}/ivl_fre_report_*.csv" }
    let(:file) { Dir.glob(file_pattern).first }
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let!(:enrollment) do
      FactoryBot.create(
        :hbx_enrollment,
        household: family.active_household,
        effective_on: TimeKeeper.date_of_record.next_year.beginning_of_year,
        family: family,
        kind: "individual",
        aasm_state: 'auto_renewing'
      )
    end

    after do
      File.delete(file) if File.exist?(file)
    end

    context 'csv generation' do
      before do
        subject.call(params)
        @csv = CSV.read(file, :headers => true)
      end

      it "creates csv file" do
        expect(@csv.size).to be > 0
      end

      it "returns correct headers" do
        expect(@csv.headers).to eq %w[family_id hbx_id notice_generated]
      end
    end

    context "when person with fre notice present" do
      let!(:message) do
        message = person.inbox.messages.create(
          subject: "Your Plan Enrollment for #{enrollment.effective_on.year}"
        )
        message.set(created_at: Date.new(TimeKeeper.date_of_record.year, 11, 2).end_of_day)
        message
      end

      before do
        subject.call(params)
        @csv = CSV.read(file, :headers => true)
      end

      it "should include the person that received the notice" do
        expect(@csv.size).to eq 1
        expect(@csv[0]['family_id']).to eq family.id.to_s
        expect(@csv[0]['hbx_id']).to eq person.hbx_id.to_s
        expect(@csv[0]['notice_generated']).to eq 'true'
      end
    end
  end

  describe 'failed_validation_report mode' do
    let(:params) do
      { mode: 'failed_validation_report',
        effective_on: TimeKeeper.date_of_record.next_year.beginning_of_year,
        created_on: Date.new(TimeKeeper.date_of_record.year, 11, 1) }
    end
    let(:file_pattern) { "#{Rails.root}/ivl_fre_failed_validation_report_*.csv" }
    let(:file) { Dir.glob(file_pattern).first }
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let!(:enrollment) do
      FactoryBot.create(
        :hbx_enrollment,
        household: family.active_household,
        effective_on: TimeKeeper.date_of_record.next_year.beginning_of_year,
        family: family,
        kind: "individual",
        aasm_state: 'auto_renewing'
      )
    end

    after do
      File.delete(file) if File.exist?(file)
    end

    context 'csv generation' do
      before do
        subject.call(params)
        @csv = CSV.read(file, :headers => true)
      end

      it "creates csv file" do
        expect(@csv.size).to be > 0
      end

      it "returns correct headers" do
        expect(@csv.headers).to eq %w[hbx_id validation_result output]
      end
    end

    context "when multiple people present" do
      let(:person_two) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
      let(:family_two) { FactoryBot.create(:family, :with_primary_family_member, person: person_two) }
      let!(:enrollment_two) do
        FactoryBot.create(
          :hbx_enrollment,
          household: family_two.active_household,
          effective_on: TimeKeeper.date_of_record.next_year.beginning_of_year,
          family: family_two,
          kind: "individual",
          aasm_state: 'auto_renewing'
        )
      end

      let!(:message) do
        message = person.inbox.messages.create(
          subject: "Your Plan Enrollment for #{enrollment.effective_on.year}"
        )
        message.set(created_at: Date.new(TimeKeeper.date_of_record.year, 11, 2).end_of_day)
        message
      end

      before do
        subject.call(params)
        @csv = CSV.read(file, :headers => true)
      end

      it "should export the family that did not receive fre notice" do
        expect(@csv.size).to eq 1
        expect(@csv[0]['hbx_id']).to eq person_two.hbx_id.to_s
        expect(@csv[0]['output']).to be_blank
        expect(@csv[0]['validation_result']).to eq 'success'
      end
    end
  end
end