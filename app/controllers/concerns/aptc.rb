# frozen_string_literal: true

module Aptc
  def get_shopping_tax_household_from_person(person, year)
    if person.present? && person.is_consumer_role_active?
      person.primary_family.latest_household.latest_active_tax_household_with_year(year) rescue nil
    else
      nil
    end
  end

  def fetch_max_aptc(enrollment, tax_household = nil)
    if EnrollRegistry.feature_enabled?(:temporary_configuration_enable_multi_tax_household_feature)
      ::Operations::PremiumCredits::FindAptc.new.call({hbx_enrollment: enrollment, effective_on: enrollment.effective_on}).value!
    else
      tax_household&.total_aptc_available_amount_for_enrollment(enrollment, enrollment.effective_on)
    end
  end

  def fetch_elected_aptc(max_aptc)
    default_aptc_percentage = EnrollRegistry[:enroll_app].setting(:default_aptc_percentage).item
    (max_aptc * default_aptc_percentage) / 100
  end
end
