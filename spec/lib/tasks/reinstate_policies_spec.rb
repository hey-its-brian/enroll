# frozen_string_literal: true

require 'rails_helper'

describe 'Reinstate HBX terminated enrollments', :dbclean => :around_each do
  let(:family) { FactoryBot.create(:family, :with_primary_family_member) }
  let(:enrollment) do
    enr = FactoryBot.build(:hbx_enrollment,
                           :terminated,
                           family: family,
                           effective_on: Date.new(2025, 1, 1),
                           terminated_on: Date.new(2025, 1, 31))
    enr.workflow_state_transitions = [
      FactoryBot.build(:workflow_state_transition, from_state: 'shopping', to_state: 'coverage_terminated', transition_at: enr.terminated_on)
    ]
    enr.save!
    enr
  end

  before do
    allow_any_instance_of(HbxEnrollment).to receive(:is_shop?).and_return(false)
  end

  describe 'reinstate_policies:reinstate' do
    before do
      load File.expand_path("#{Rails.root}/lib/tasks/reinstate_policies.rake", __FILE__)
      Rake::Task.define_task(:environment)
      Rake::Task["reinstate_policies:reinstate"].reenable
    end

    it 'should nullify the term reason' do
      Rake::Task["reinstate_policies:reinstate"].invoke(enrollment.hbx_id)
      expect(enrollment.reload.terminate_reason).to eq nil
    end

    context "when current year IAP applications are determined between the enrollment's termination date and the new effective date" do
      let!(:intervening_application) do
        FactoryBot.create(:financial_assistance_application, family_id: enrollment.family.id, assistance_year: enrollment.coverage_year, submitted_at: enrollment.terminated_on + 1.day)
      end

      it 'should log a warning message' do
        expect { Rake::Task["reinstate_policies:reinstate"].invoke(enrollment.hbx_id) }
          .to output(/WARNING: #{enrollment.coverage_year} year IAP Applications for Family \(HBXID: #{enrollment.family.primary_applicant.person.hbx_id}\) submitted after/).to_stdout
      end

      it 'should include application details in warning message' do
        expect { Rake::Task["reinstate_policies:reinstate"].invoke(enrollment.hbx_id) }
          .to output(%r{#{intervening_application.hbx_id} \(\d{2}/\d{2}/\d{2}\)}).to_stdout
      end

      it 'should include termination date in warning message' do
        termination_date = enrollment.workflow_state_transitions.first.transition_at
        expect { Rake::Task["reinstate_policies:reinstate"].invoke(enrollment.hbx_id) }
          .to output(/terminated or canceled on #{Regexp.escape(termination_date.to_s)}/).to_stdout
      end
    end
  end
end
