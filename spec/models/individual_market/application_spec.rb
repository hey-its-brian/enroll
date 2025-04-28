# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndividualMarket::Application, type: :model do
  let(:application) { FactoryBot.create(:individual_market_application, :with_primary) }

  describe 'associations' do
    it 'belongs to a family' do
      expect(application.family).to be_a(Family)
    end

    context 'when creating' do
      it 'sets the _type field correctly' do
        expect(application._type).to eq('IndividualMarket::Application')
      end

      it 'is an instance of IndividualMarket::Application' do
        application
        expect(Sbm::Application.first).to be_a(IndividualMarket::Application)
      end

      it 'is an instance of Sbm::Application' do
        application
        expect(Sbm::Application.first).to be_a(Sbm::Application)
      end
    end
  end

  describe 'fields' do
    it { is_expected.to have_field(:hbx_id).of_type(String) }
    it { is_expected.to have_field(:effective_on).of_type(Date) }
    it { is_expected.to have_field(:submitted_at).of_type(DateTime) }
    it { is_expected.to have_field(:assistance_year).of_type(Integer) }
    it { is_expected.to have_field(:predecessor_id).of_type(BSON::ObjectId) }
    it { is_expected.to have_field(:origin).of_type(Symbol) }
    it { is_expected.to have_field(:generation_reason).of_type(Symbol) }
  end

  describe 'validations' do
    describe '#no_duplicate_relationships' do
      let(:applicant1) { application.primary_applicant }
      let(:applicant2) { FactoryBot.build(:individual_market_applicant, :dependent) }
      let(:relationship1) { FactoryBot.build(:individual_market_relationship, source_id: applicant1.id, relative_id: applicant2.id, kind: 'spouse') }

      before do
        application.applicants = [applicant1, applicant2]
      end

      context 'when there are no duplicate relationships' do
        it 'is valid' do
          application.relationships = [relationship1]
          expect(application.valid?).to be true
        end
      end

      context 'when there are duplicate relationships' do
        let(:relationship2) { FactoryBot.build(:individual_market_relationship, source_id: applicant1.id, relative_id: applicant2.id, kind: 'child') }

        it 'is invalid' do
          application.relationships = [relationship1, relationship2]
          expect(application.valid?).to be false
        end

        it 'adds an error message' do
          application.relationships = [relationship1, relationship2]
          application.valid?
          expect(application.errors[:relationships]).to include('contains duplicate relationships (same source and relative)')
        end
      end

      context 'when relationships have different source and relative pairs' do
        let(:relationship2) { FactoryBot.build(:individual_market_relationship, source_id: applicant2.id, relative_id: applicant1.id, kind: 'parent') }

        it 'is valid' do
          application.relationships = [relationship1, relationship2]
          expect(application.valid?).to be true
        end
      end
    end

    describe 'enumeration fields' do
      shared_examples_for 'an enumeration field' do |field, valid_values|
        context 'when set to valid values' do
          valid_values.each do |value|
            it "is valid with :#{value}" do
              application.send("#{field}=", value)
              expect(application.valid?).to be true
            end
          end
        end

        context 'when set to invalid value' do
          it "is invalid with an unrecognized value" do
            application.send("#{field}=", :invalid_value)
            expect(application.valid?).to be false
            expect(application.errors[field]).to include('is not included in the list')
          end

          it "is invalid with nil" do
            application.send("#{field}=", nil)
            expect(application.valid?).to be false
            expect(application.errors[field]).to include('is not included in the list')
          end
        end
      end

      context 'origin validation' do
        it_behaves_like 'an enumeration field', :origin, %i[user system admin data_import migration]
      end

      context 'generation_reason validation' do
        it_behaves_like 'an enumeration field', :generation_reason, %i[manual rop_expiration renewal]
      end
    end

    describe 'assistance_year validation' do
      context 'when set to current year' do
        it 'returns true' do
          application.assistance_year = Date.today.year
          expect(application.valid?).to be true
        end
      end

      context 'when set to a year less than 2025' do
        it 'returns false' do
          application.assistance_year = 2024
          expect(application.valid?).to be false
          expect(application.errors[:assistance_year]).to include('must be greater than or equal to 2025')
        end
      end

      context 'when set to a year greater than 2025' do
        it 'returns true' do
          application.assistance_year = 2026
          expect(application.valid?).to be true
        end
      end

      context 'when set to nil' do
        it 'returns false' do
          application.assistance_year = nil
          expect(application.valid?).to be false
          expect(application.errors[:assistance_year]).to include("can't be blank")
        end
      end
    end
  end

  describe 'state machine' do
    let(:failure_comment) { 'Missing information' }
    let(:reset_comment) { 'Fixing application' }
    let(:expire_comment) { 'Application expired' }

    context 'default state' do
      it 'has an initial state by default' do
        expect(application.current_state).to eq(:initial)
      end

      it 'has no state history records initially' do
        expect(application.state_histories.count).to eq(0)
      end
    end

    describe 'state transitions' do
      context 'from initial state' do
        let(:application) { FactoryBot.create(:individual_market_application, :initial) }

        it 'can transition to submission_failed' do
          expect(application.may_failed_submission?).to be true
          application.failed_submission('Validation errors')
          expect(application.current_state).to eq(:submission_failed)
        end

        it 'can transition to submitted' do
          expect(application.may_submit?).to be true
          application.submit('Application submitted')
          expect(application.current_state).to eq(:submitted)
        end

        it 'can transition to expired' do
          expect(application.may_expire?).to be true
          application.expire('Application expired')
          expect(application.current_state).to eq(:expired)
        end

        it 'cannot transition to determined or determination_failed' do
          expect(application.may_determine?).to be false
          expect(application.may_failed_determination?).to be false
          expect { application.determine }.to raise_error(ArgumentError)
          expect { application.failed_determination }.to raise_error(ArgumentError)
        end

        it 'cannot transition to initial (already there)' do
          expect(application.may_reset?).to be false
          expect { application.reset }.to raise_error(ArgumentError)
        end
      end

      context 'from submission_failed state' do
        let(:application) { FactoryBot.create(:individual_market_application, :submission_failed) }

        it 'can transition to initial via reset' do
          expect(application.may_reset?).to be true
          application.reset('Resetting application')
          expect(application.current_state).to eq(:initial)
        end

        it 'can transition to submitted' do
          expect(application.may_submit?).to be true
          application.submit('Re-submitting application')
          expect(application.current_state).to eq(:submitted)
        end

        it 'can transition to expired' do
          expect(application.may_expire?).to be true
          application.expire('Application expired')
          expect(application.current_state).to eq(:expired)
        end

        it 'cannot transition to determined or determination_failed' do
          expect(application.may_determine?).to be false
          expect(application.may_failed_determination?).to be false
        end

        it 'cannot transition to submission_failed (already there)' do
          expect(application.may_failed_submission?).to be false
          expect { application.failed_submission }.to raise_error(ArgumentError)
        end
      end

      context 'from submitted state' do
        let(:application) { FactoryBot.create(:individual_market_application, :submitted) }

        it 'can transition to determined' do
          expect(application.may_determine?).to be true
          application.determine('Application determined')
          expect(application.current_state).to eq(:determined)
        end

        it 'can transition to determination_failed' do
          expect(application.may_failed_determination?).to be true
          application.failed_determination('Determination failed')
          expect(application.current_state).to eq(:determination_failed)
        end

        it 'can transition to expired' do
          expect(application.may_expire?).to be true
          application.expire('Application expired')
          expect(application.current_state).to eq(:expired)
        end

        it 'cannot transition to initial or submission_failed' do
          expect(application.may_reset?).to be false
          expect(application.may_failed_submission?).to be false
        end

        it 'cannot transition to submitted (already there)' do
          expect(application.may_submit?).to be false
          expect { application.submit }.to raise_error(ArgumentError)
        end
      end

      context 'from determined state' do
        let(:application) { FactoryBot.create(:individual_market_application, :determined) }

        describe 'valid transitions' do
          it 'can transition to expired' do
            expect(application.may_expire?).to be true
            application.expire(expire_comment)
            expect(application.current_state).to eq(:expired)
          end
        end

        describe 'invalid transitions' do
          it 'cannot transition to initial state' do
            expect(application.may_reset?).to be false
          end

          it 'cannot transition to submission_failed state' do
            expect(application.may_failed_submission?).to be false
          end

          it 'cannot transition to submitted state' do
            expect(application.may_submit?).to be false
          end

          it 'cannot transition to determination_failed state' do
            expect(application.may_failed_determination?).to be false
          end

          it 'cannot transition to determined state (already there)' do
            expect(application.may_determine?).to be false
          end
        end
      end

      context 'from determination_failed state' do
        let(:application) { FactoryBot.create(:individual_market_application, :determination_failed) }

        it 'can transition to expired' do
          expect(application.may_expire?).to be true
          application.expire('Application expired')
          expect(application.current_state).to eq(:expired)
        end

        it 'cannot transition to other states' do
          expect(application.may_reset?).to be false
          expect(application.may_failed_submission?).to be false
          expect(application.may_submit?).to be false
          expect(application.may_failed_determination?).to be false
          expect(application.may_determine?).to be false
        end
      end

      context 'from expired state' do
        let(:application) { FactoryBot.create(:individual_market_application, :expired) }

        it 'cannot transition to any other state' do
          expect(application.may_reset?).to be false
          expect(application.may_failed_submission?).to be false
          expect(application.may_submit?).to be false
          expect(application.may_failed_determination?).to be false
          expect(application.may_determine?).to be false
          expect(application.may_expire?).to be false
        end
      end
    end

    describe 'state history tracking' do
      let(:state_history) { application.state_histories.first }

      before :each do
        application.submit(comment, reason)
        application.save!
        application.reload
      end

      context 'when comment and reason are provided' do
        let(:comment) { 'Completed application' }
        let(:reason) { 'COMPLETE' }

        it 'persists from state' do
          expect(state_history.from_state).to eq(:initial)
        end

        it 'persists to state' do
          expect(state_history.to_state).to eq(:submitted)
        end

        it 'persists event' do
          expect(state_history.event).to eq(:submit)
        end

        it 'persists comment' do
          expect(state_history.comment).to eq('Completed application')
        end

        it 'persists reason code' do
          expect(state_history.reason).to eq('COMPLETE')
        end

        it 'persists effective_on' do
          expect(state_history.effective_on).not_to be_nil
        end
      end

      context 'when comment and reason are not provided' do
        let(:comment) { nil }
        let(:reason) { nil }

        it 'persists nil comment' do
          expect(state_history.comment).to be_nil
        end

        it 'persists nil reason' do
          expect(state_history.reason).to be_nil
        end
      end
    end

    describe 'error handling' do
      it 'raises error when transitioning from an invalid state' do
        application.current_state = :invalid_state

        expect { application.submit }.to raise_error(ArgumentError, /Invalid from_state/)
      end

      it 'raises error when attempting an invalid transition' do
        application.submit # Move to submitted state

        expect { application.submit }.to raise_error(ArgumentError, /Cannot submit from state/)
      end
    end
  end

  describe '#only_one_primary_applicant' do
    let(:primary_applicant) { FactoryBot.build(:individual_market_applicant, is_primary_applicant: true) }
    let(:dependent_applicant) { FactoryBot.build(:individual_market_applicant, :dependent) }
    let(:another_primary_applicant) { FactoryBot.build(:individual_market_applicant, is_primary_applicant: true) }

    context 'without primary applicant' do
      before do
        application.applicants = [dependent_applicant]
      end

      it 'is invalid' do
        expect(application.valid?).to be false
        expect(application.errors[:applicants]).to include('must have exactly one primary applicant')
      end
    end

    context 'with multiple primary applicants' do
      before do
        application.applicants = [primary_applicant, another_primary_applicant]
      end

      it 'is invalid' do
        expect(application.valid?).to be false
        expect(application.errors[:applicants]).to include('must have exactly one primary applicant')
      end
    end

    context 'with one primary applicant' do
      before do
        application.applicants = [primary_applicant, dependent_applicant]
      end

      it 'is valid' do
        expect(application.valid?).to be true
      end
    end
  end
end
