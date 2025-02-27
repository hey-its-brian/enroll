# frozen_string_literal: true

require 'rails_helper'

describe 'Reinstate HBX terminated enrollments', :dbclean => :around_each do
  let(:enrollment) do
    FactoryBot.create(:hbx_enrollment, :terminated, family: FactoryBot.create(:family, :with_primary_family_member))
  end

  describe 'reinstate_policies:reinstate' do

    before do
      load File.expand_path("#{Rails.root}/lib/tasks/reinstate_policies.rake", __FILE__)
      Rake::Task.define_task(:environment)
      Rake::Task["reinstate_policies:reinstate"].reenable
      Rake::Task["reinstate_policies:reinstate"].invoke([enrollment.hbx_id])
    end

    it 'should nullify the term reason' do
      expect(enrollment.reload.terminate_reason).to eq nil
    end
  end
end
