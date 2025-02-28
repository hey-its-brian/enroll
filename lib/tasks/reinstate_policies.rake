# example call: `bundle exec rake "reinstate_policies:reinstate[<HBX_ID_1> <HBX_ID_2]> ... <HBX_ID_N>]"`
namespace :reinstate_policies do
  desc "Silently reinstate terminated policies with given HBX ids"
  task :reinstate, [:ids] => :environment do |t, args|
    raise ArgumentError, "No IDs provided. Please provide a comma-separated list of IDs." unless args[:ids].present?

    hbx_ids = args[:ids].to_s.split(' ').uniq
    hbx_ids.uniq.each do |id|
      puts "Starting Reinstating ID... #{id}"
      base_enrollment = HbxEnrollment.by_hbx_id(id).first
      if base_enrollment.present?
        if (base_enrollment.coverage_canceled? || base_enrollment.coverage_terminated?)
          reinstate_date = if base_enrollment.coverage_canceled?
                             base_enrollment.effective_on
                           elsif base_enrollment.coverage_terminated?
                             if base_enrollment.terminated_on == TimeKeeper.date_of_record.end_of_year
                               base_enrollment.update_attributes(aasm_state: "coverage_canceled", terminated_on: "")
                               base_enrollment.effective_on
                             else
                               base_enrollment.terminated_on.next_day
                             end
                           end
          unless (base_enrollment.effective_on.beginning_of_year..base_enrollment.effective_on.end_of_year).include?(reinstate_date)
            puts "Unable to Reinstate Enrollment #{id}, Reinstate date outside Current Year, Enrollment Status: #{base_enrollment.try(:aasm_state)}, Effective On #{base_enrollment.effective_on}, Terminated On #{base_enrollment.terminated_on} Reinstate Date: #{reinstate_date} Family ID: #{base_enrollment.try(:subscriber).try(:hbx_id)}"
            next
          end
          overlapping_enrollments = HbxEnrollment.where({ :family_id => base_enrollment.family_id,
                                                          :kind.in => %w[individual coverall],
                                                          :effective_on.gte => reinstate_date,
                                                          :effective_on.lte => reinstate_date.end_of_year,
                                                          :coverage_kind => base_enrollment.coverage_kind,
                                                          :aasm_state.in => HbxEnrollment::ENROLLED_AND_RENEWAL_STATUSES + ["coverage_terminated"] })
          overlapping_coverage = overlapping_enrollments.any? { |enrollment| enrollment.try(:subscriber).try(:hbx_id) == base_enrollment.try(:subscriber).try(:hbx_id) }
          if overlapping_coverage
            puts "Unable to Reinstate Enrollment #{id}, Overlapping Coverage, Enrollment Status: #{base_enrollment.try(:aasm_state)}, Effective On #{base_enrollment.effective_on}, Terminated On #{base_enrollment.terminated_on}  Family ID: #{base_enrollment.try(:subscriber).try(:hbx_id)}"
            next
          end
          clone_hbx_enrollment_members = base_enrollment.hbx_enrollment_members.inject([]) do |members, hbx_enrollment_member|
            members << HbxEnrollmentMember.new({
                                                 applicant_id: hbx_enrollment_member.applicant_id,
                                                 eligibility_date: reinstate_date,
                                                 coverage_start_on: hbx_enrollment_member.coverage_start_on,
                                                 is_subscriber: hbx_enrollment_member.is_subscriber,
                                                 tobacco_use: hbx_enrollment_member.tobacco_use,
                                               })
          end
          params = {
            family: base_enrollment.family,
            household: base_enrollment.family.active_household,
            coverage_kind: base_enrollment.coverage_kind,
            enrollment_kind: base_enrollment.enrollment_kind,
            kind: base_enrollment.kind,
            predecessor_enrollment_id: base_enrollment.id,
            hbx_enrollment_members: clone_hbx_enrollment_members,
            product_id: base_enrollment.product_id,
            consumer_role_id: base_enrollment.consumer_role_id,
            rating_area_id: base_enrollment.rating_area_id,
            effective_on: reinstate_date,
            elected_aptc_pct: base_enrollment.elected_aptc_pct,
            applied_aptc_amount: base_enrollment.applied_aptc_amount,
            special_enrollment_period_id: base_enrollment.special_enrollment_period_id,
          }
          reinstate_enrollment = HbxEnrollment.new
          reinstate_enrollment.assign_attributes(params)
          if reinstate_enrollment.present? && reinstate_enrollment.may_reinstate_coverage?
            reinstate_enrollment.reinstate_coverage!(check_determination: true)
            if EnrollRegistry.feature_enabled?(:temporary_configuration_enable_multi_tax_household_feature) && base_enrollment.is_ivl_by_kind?
              TaxHouseholdEnrollment.by_enrollment_id(base_enrollment.id).each do |thhe|
                new_thhe = thhe.build_tax_household_enrollment_for(reinstate_enrollment)
                new_thhe.save
              end
            end
            reinstate_enrollment.begin_coverage!(check_determination: true) if reinstate_enrollment.may_begin_coverage?
            reinstate_enrollment.notify_of_coverage_start(false)
            enrollments = HbxEnrollment.where(
              { :family_id => base_enrollment.family_id,
                :effective_on => base_enrollment.effective_on.beginning_of_year..reinstate_enrollment.effective_on - 1.day,
                :coverage_kind => base_enrollment.coverage_kind,
                :consumer_role_id => base_enrollment.consumer_role_id,
                :product_id => base_enrollment.product_id,
                :terminate_reason => HbxEnrollment::TermReason::NON_PAYMENT,
                :"hbx_enrollment_members.applicant_id" => base_enrollment.subscriber&.applicant_id,
                :"hbx_enrollment_members.is_subscriber" => true }
            )
            enrollments.update_all(terminate_reason: nil) if enrollments.any?
            puts "Enrollment Reinstated HBXID: #{reinstate_enrollment.hbx_id} Reinstated Start Date: #{reinstate_enrollment.effective_on} Family ID: #{base_enrollment.try(:subscriber).try(:hbx_id)}"
          else
            puts "Enrollment not Eligible to Reinstate Enrollment HbxID: #{base_enrollment.hbx_id} Family ID: #{base_enrollment.try(:subscriber).try(:hbx_id)}"
          end
        else
          puts "Enrollment not in Canceled or Terminated State: #{id}, Enrollment Status: #{base_enrollment.try(:aasm_state)}, Effective On #{base_enrollment.effective_on}, Terminated On #{base_enrollment.terminated_on} Family ID: #{base_enrollment.try(:subscriber).try(:hbx_id)}"
        end
      else
        puts "Unable to Reinstate, Enrollment not found: #{id}"
      end
    end
  end

  desc "Silently reinstate terminated policies with given HBX ids by nullifying the term reason"
  task :force_reinstate, [:ids] do |t, args|
    hbx_ids = args[:ids].to_s.split(',').uniq
    hbx_ids.uniq.each do |id|
      enrollment = HbxEnrollment.where(hbx_id: id).first
      enrollment&.update_attributes(terminate_reason: nil)
    end
  end
end
