# frozen_string_literal: true

#qhp determination results page
class IvlQhpEligibilityResultsPage

  def self.qhp_continue_to_shop_for_plans
    '.interaction-click-control-continue-to-shop-for-plans'
  end

  def self.qhp_view_my_applications
    '.interaction-click-control-view-my-applications'
  end

  def self.uqhp_eligible_section
    '[data-cuke="determined-uqhp-eligible-section"]'
  end

  def self.csr_eligible_section
    '[data-cuke="determined-csr-eligible-section"]'
  end

  def self.totally_ineligible_section
    '[data-cuke="determined-totally-ineligible-section"]'
  end

  def self.not_applying_coverage_section
    '[data-cuke="not-applying-coverage-section"]'
  end
end