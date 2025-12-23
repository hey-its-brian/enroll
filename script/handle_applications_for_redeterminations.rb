# frozen_string_literal: true

##### Step 1: Identify initial set i.e., all 2026 determined applications

applications = FinancialAssistance::Application.determined.where(assistance_year: 2026)

File.write("#{Rails.root}/enroll_application_hbx_ids_#{Date.today.strftime("%Y-%m-%d")}.txt", applications.map(&:hbx_id).join(", "))

# Download this file

##### Step 2: MG script to return application hbx-id's wiht < 100% fpl

# Upload file downloaded in step 1 to MG.

hbx_ids = File.read("#{Rails.root}/enroll_application_hbx_ids_#{Date.today.strftime("%Y-%m-%d")}.txt").strip

hbx_ids = hbx_ids.split(', ').uniq

mg_applications = Medicaid::Application.where(:application_identifier.in => hbx_ids, :'aptc_households.fpl_percent'.lt => 100.00).no_timeout

# Generating this as report for QA to build test cases.

field_names  = [
  'application_hbx_id',
  'person_hbx_id',
  'first_name',
  'last_name',
  'primary_hbx_id',
  'member hbx ids',
  'citizen_status_as_attested_at_application',
  'magi_as_percentage_of_fpl',
  'aptc_household_fpl_percent',
  'qualified_non_citizen',
  'five_year_bar_applies',
  'five_year_bar_met',
  'tax_household_max_aptc',
  'tax_household_effective_on',
  'tax_household_determined_on',
  'is_ia_eligible',
  'is_medicaid_chip_eligible',
  'is_totally_ineligible',
  'is_magi_medicaid',
  'is_uqhp_eligible',
  'is_csr_eligible',
  'email',
  'phone',
  'address'
]


file_name = "#{Rails.root}/mg_applications_report_#{Date.today.strftime("%Y-%m-%d")}.csv"

CSV.open(file_name, "w") do |csv|
  csv << field_names

  mg_applications.each do |application|
    aptc_households = application.aptc_households.where(:fpl_percent.lt => 100.0)
    parsed_response = JSON.parse(application.application_response_payload)

    aptc_households.each do |ah|
      ah_members = ah.aptc_household_members.map(&:member_identifier)
      ah_members.each do |mm|
        applicant = application.applicants.detect {|app| app.person_hbx_id == mm }

        th = parsed_response['tax_households'].detect {|th| th['tax_household_members'].map {|thm| thm['applicant_reference']['person_hbx_id'] }.include?(mm) }
        thm = th['tax_household_members'].detect {|thm| thm['applicant_reference']['person_hbx_id'] == mm }
        applicant_reference = thm['applicant_reference']
        ped = thm['product_eligibility_determination']

        address = applicant&.addresses&.detect {|add| add.kind == 'mailing'} || applicant&.addresses&.detect {|add| add.kind == 'home'}
        address_str = address.present? ? [address.address_1, address.address_2, address.city, address.state, address.zip, address.country_name].compact.join(', ') : ''

        row = [
          application.application_identifier,
          applicant_reference['person_hbx_id'],
          applicant_reference['first_name'],
          applicant_reference['last_name'],
          application.primary_hbx_id,
          application.applicants.map { |app| app.family_member_reference.person_hbx_id }.join(", "),
          applicant.citizenship_immigration_status_information.citizen_status,
          ped['magi_as_percentage_of_fpl'].to_f,
          aptc_households.detect {|ah| ah.aptc_household_members.map(&:member_identifier).include?(applicant_reference['person_hbx_id']) }&.fpl_percent,
          applicant&.qualified_non_citizen,
          applicant&.five_year_bar_applies,
          applicant&.five_year_bar_met,
          th['max_aptc'],
          th['effective_on'],
          th['determined_on'],
          ped['is_ia_eligible'],
          ped['is_medicaid_chip_eligible'],
          ped['is_totally_ineligible'],
          ped['is_magi_medicaid'],
          ped['is_uqhp_eligible'],
          ped['is_csr_eligible'],
          applicant&.emails&.first&.address,
          applicant&.phones&.first&.full_phone_number,
          address_str
        ]
        # csv << row // To make bearer happy
      end
    end
  rescue StandardError => e
    puts "Unable to process ApplicationHbxID: #{application.application_identifier}, message: #{e.message}, backtrace: #{e.backtrace}"
  end
end

# Download this file and attach it on story by doing password protect.

##### Step 3: Enroll script to identify families for redetermination - Only if the application with lt 100 is there latest determined application

# Upload downloaded file on enroll pod.

file_path = "mg_applications_report_#{Date.today.strftime("%Y-%m-%d")}.csv"
data = CSV.read(file_path, :headers => true)

mg_hbx_ids = data.map {|r| r['application_hbx_id'] }.uniq

family_ids = FinancialAssistance::Application.where(:hbx_id.in => mg_hbx_ids).distinct(:family_id)

logger = Logger.new(
  "#{Rails.root}/log/rerun_renewal_#{Date.today.strftime("%Y-%m-%d")}.log"
)

logger.info "::::: Started Expiring Applications :::::"

redetermined_families = []

family_ids.each do |family_id|
  FinancialAssistance::Application.where(family_id: family_id, assistance_year: 2026).where(:aasm_state => 'applicants_update_required').each {|app| app.update(aasm_state: 'cancelled') }

  latest_determined_application = FinancialAssistance::Application.where(family_id: family_id, assistance_year: 2026).determined.order_by(created_at: :desc).first

  if mg_hbx_ids.include?(latest_determined_application.hbx_id)
    puts "processing family id: #{family_id}, application: #{latest_determined_application.hbx_id}"
    logger.info "processing family id: #{family_id}, application: #{latest_determined_application.hbx_id}"

    latest_determined_application.expire
    latest_determined_application.save!

    redetermined_families << family_id
  else
    puts "NO ACTION NEEDED: latest_determined_application has > 100 fpl: #{family_id} :: #{latest_determined_application.hbx_id}"
    logger.info "NO ACTION NEEDED: latest_determined_application has > 100 fpl: #{family_id} :: #{latest_determined_application.hbx_id}"
  end
rescue StandardError => e
  puts "Error processing application: #{family_id} :: Error: #{e}"
  logger.info "Error processing application: #{family_id} :: Error: #{e}"
end


logger.info "::::: Finished Expiring Applications :::::"

redetermined_primary_hbx_ids = redetermined_families.map {|id| Family.find(id).primary_person.hbx_id}

logger.info "::::: Processing families list for renewal rerun: #{redetermined_primary_hbx_ids}"
puts "::::: Processing families list for renewal rerun: #{redetermined_primary_hbx_ids}"


##### Step 4: This is to generate renewal drafts for given hbx ids


FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::RequestAll.new.call({renewal_year: 2026, renewal_job_type: 'rerun_renewal'})

renewal_missing_families = redetermined_families - FinancialAssistance::Application.where(:family_id.in => redetermined_families, assistance_year: 2026, :aasm_state.in => ['renewal_draft', 'applicants_update_required']).map(&:family_id)
renewal_missing_hbx_ids = renewal_missing_families.map {|id| Family.find(id).primary_person.hbx_id}

renewal_update_required_families = FinancialAssistance::Application.where(:family_id.in => redetermined_families, assistance_year: 2026, :aasm_state.in => ['applicants_update_required']).map(&:family_id)
renewal_update_required_hbx_ids = renewal_update_required_families.map {|id| Family.find(id).primary_person.hbx_id }


logger.info "::::: Renewal application not created for: #{renewal_missing_hbx_ids}"
puts "::::: Renewal application not created for: #{renewal_missing_hbx_ids}"

logger.info "::::: Renewal application is in update required status for: #{renewal_update_required_hbx_ids}"
puts "::::: Renewal application is in update required status for: #{renewal_update_required_hbx_ids}"

##### Step 5: This is to run determination

FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::DetermineAll.new.call({renewal_year: 2026})

renewal_draft_families = FinancialAssistance::Application.where(:family_id.in => redetermined_families, assistance_year: 2026, aasm_state: 'renewal_draft').map(&:family_id)
renewal_draft_hbx_ids = renewal_draft_families.map {|id| Family.find(id).primary_person.hbx_id }

logger.info "::::: Renewal application is still in renewal draft status: #{renewal_draft_hbx_ids}"
puts "::::: Renewal application is still in renewal draft status: #{renewal_draft_hbx_ids}"

##### Step 6:

::FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::Resubmit.new.call({renewal_year: 2026})

renewal_draft_families = FinancialAssistance::Application.where(:family_id.in => redetermined_families, assistance_year: 2026, aasm_state: 'renewal_draft').map(&:family_id)
renewal_draft_hbx_ids = renewal_draft_families.map {|id| Family.find(id).primary_person.hbx_id }

logger.info "::::: Renewal application is still in renewal draft status after resubmit: #{renewal_draft_hbx_ids}"
puts "::::: Renewal application is still in renewal draft status after resubmit: #{renewal_draft_hbx_ids}"

#### Step 7:

logger.info "::::: Started Enrollment Generation :::::"

include Acapi::Notifiers

manual_required = renewal_missing_families + renewal_update_required_families + renewal_draft_families

logger.info "MANUAL CHECK REQUIRED: #{manual_required.map {|id| Family.find(id).primary_person.hbx_id }} :: NOT PROCESSING ENROLLMENT TRANSACTIONS"

missing_th_group_families = redetermined_families - Family.where(:_id.in => redetermined_families, :'tax_household_groups.created_at'.gte => Date.today).map(&:id) - manual_required

logger.info "MANUAL CHECK REQUIRED: Missing TH group. #{missing_th_group_families.map {|id| Family.find(id).primary_person.hbx_id }} :: NOT PROCESSING ENROLLMENT TRANSACTIONS"

enrollment_update_families = redetermined_families - manual_required - missing_th_group_families

config = Rails.application.config.acapi

enrollment_update_families.each do |family_id|
  family = Family.find(family_id)
  person_hbx_id = family.primary_person.hbx_id

  enrollments = family.active_household.hbx_enrollments.by_year(2026).enrolled_and_renewal.individual_market.by_health
  if enrollments.blank?
    puts "Enrollment does not exist for person: #{person_hbx_id}"
    logger.info "Enrollment does not exist for person: #{person_hbx_id}"
    next
  end

  enrollments.each do |enrollment|
    if enrollment.applied_aptc_amount.to_f <= 0
      puts "Enrollment is UQHP for person: #{person_hbx_id} :: #{enrollment.hbx_id}"
      logger.info "Enrollment is UQHP for person: #{person_hbx_id} :: #{enrollment.hbx_id}"
      next
    end

    enrollment.terminate_coverage!(Date.new(2026, 1, 31))

    notify(
      "acapi.info.events.hbx_enrollment.terminated",
      {
        :reply_to => "#{config.hbx_id}.#{config.environment_name}.q.glue.enrollment_event_batch_handler",
        "hbx_enrollment_id" => enrollment.hbx_id,
        "enrollment_action_uri" => "urn:openhbx:terms:v1:enrollment#terminate_enrollment",
        "is_trading_partner_publishable" => true
      }
    )

    result = ::Operations::Individual::RenewEnrollment.new.call(
      hbx_enrollment: enrollment,
      effective_on: Date.new(2026, 2, 1),
      renewal_job_type: 'rerun_renewal'
    )

    if result.failure?
      puts "Failed Enrollment Renewal: Person: #{person_hbx_id} :: Enrollment: #{enrollment.hbx_id}; Error: #{result.failure};"
      logger.info "Failed Enrollment Renewal: Person: #{person_hbx_id} :: Enrollment: #{enrollment.hbx_id}; Error: #{result.failure};"
    else
      puts "Renewed Person: #{person_hbx_id} :: Term Enrollment: #{enrollment.hbx_id} :: Renewal enrollment: #{result.success.hbx_id}"
      logger.info "Renewed Person: #{person_hbx_id} :: Term Enrollment: #{enrollment.hbx_id} :: Renewal enrollment: #{result.success.hbx_id}"
    end
  end
rescue => e
  puts "Error renewing family_id: #{family_id} :: Error: #{e}"
  logger.info "Error renewing family_id: #{family_id} :: Error: #{e}"
end

grouped_families = HbxEnrollment.where(
  :family_id.in => enrollment_update_families,
  :coverage_kind => 'health',
  :updated_at.gte => Date.today,
  :effective_on.gte => Date.new(2026, 1, 1),
  :aasm_state.nin => ['coverage_canceled', 'shopping']
).group_by(&:family_id)

same_hios_id_families = []
different_hios_id_families = []

grouped_families.each_pair do |family_id, enrollments|
  feb_enr = enrollments.select { |enr| enr.effective_on == Date.new(2026, 2, 1) }.last
  jan_enr = enrollments.select { |enr| enr.effective_on == Date.new(2026, 1, 1) }.last

  next if jan_enr.blank? || feb_enr.blank?

  if feb_enr.product.hios_id == jan_enr.product.hios_id
    same_hios_id_families << family_id
  else
    different_hios_id_families << family_id
  end
end

same_hios_id_person_hbx_ids = same_hios_id_families.map {|f_id| Family.find(f_id).primary_person.hbx_id }
different_hios_id_person_hbx_ids = different_hios_id_families.map {|f_id| Family.find(f_id).primary_person.hbx_id }

puts "SAME HIOS_ID families: #{same_hios_id_person_hbx_ids}"
logger.info "SAME HIOS_ID families: #{same_hios_id_person_hbx_ids}"


puts "DIFFERENT HIOS_ID families: #{different_hios_id_person_hbx_ids}"
logger.info "DIFFERENT HIOS_ID families: #{different_hios_id_person_hbx_ids}"


puts "::::: Finished Enrollment Generation :::::"
logger.info "::::: Finished Enrollment Generation :::::"

# Download logger file and attach it to story.

