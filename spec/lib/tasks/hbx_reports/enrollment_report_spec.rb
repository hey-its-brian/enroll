# frozen_string_literal: true

require 'rspec'
require 'csv'

describe 'Enrollment Report', :dbclean => :after_each do
  context 'reports:enrollment_report_generate' do
    let(:start_on) { "1/1/2025" }
    let(:end_on) { "1/1/2025" }

    before do
      ClimateControl.modify start_on: start_on, end_on: end_on do
        load File.expand_path("#{Rails.root}/lib/tasks/hbx_reports/enrollment_report.rake", __FILE__)
        Rake::Task.define_task(:environment)
        Rake::Task["reports:enrollment_report_generate"].invoke
      end
    end

    it "should generate the proper report" do
      file_name = "#{Rails.root}/enroll_enrollment_report.csv"
      expect(File.exist?(file_name)).to eq(true)
    end

    it "contains exchange kind in the headers" do
      CSV.read("#{Rails.root}/enroll_enrollment_report.csv").first.include?("Exchange Kind")
    end

  end
end