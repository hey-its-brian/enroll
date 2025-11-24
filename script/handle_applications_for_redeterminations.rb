# frozen_string_literal: true

##### Step 1: Identify initial set i.e., all 2026 determined applications

applications = FinancialAssistance::Application.determined.where(assistance_year: 2026)

File.write("#{Rails.root}/enroll_application_hbx_ids.txt", applications.map(&:hbx_id).join(", "))

##### Step 2: MG script to return application hbx-id's wiht < 100% fpl

hbx_ids = File.read("#{Rails.root}/enroll_application_hbx_ids.txt").strip

hbx_ids = hbx_ids.split(', ')

mg_applications = Medicaid::Application.where(:application_identifier.in => hbx_ids, :'aptc_households.fpl_percent'.lt => 100.00)

File.write("#{Rails.root}/mg_application_hbx_ids.txt", mg_applications.map(&:hbx_id).join(", "))

##### Step 3: Enroll script to identify families for redetermination - Only if the application with lt 100 is there latest determined application

mg_hbx_ids = File.read("#{Rails.root}/mg_application_hbx_ids.txt").strip

mg_hbx_ids = mg_hbx_ids.split(', ')

family_ids = FinancialAssistance::Application.where(:hbx_id.in => mg_hbx_ids).distinct(family_id)

family_ids.each do |family_id|
  latest_determined_application = FinancialAssistance::Application.where(family_id: family_id, application_year: 2026).determined.order_by(created_at: :desc).first

  if mg_hbx_ids.include?(latest_determined_application.hbx_id)
    application = ::FinancialAssistance::Application.where(hbx_id: hbx_id).last

    puts "processing family id: #{family_id}, application: #{hbx_id}"

    application.expire
    application.save!
  end
rescue StandardError => e
  puts "Error processing application: #{family_id} :: Error: #{e}"
end



##### Step 4: This is to generate renewal drafts for given hbx ids

FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::RequestAll.new.call({renewal_year: 2026, renewal_job_type: 'rerun_renewal'})


##### Step 5: This is to run determination

FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::DetermineAll.new.call({renewal_year: 2026})

##### Step 6:

::FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::Resubmit.new.call({renewal_year: 2026})





