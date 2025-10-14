# frozen_string_literal: true

#qhp current applications page
class IvlQhpCurrentApplicationsPage

  def self.prospective_year_banner
    '[data-cuke="prospective-year-banner"]'
  end

  def self.year_application_accordion
    '[data-cuke="year-application-accordion"]'
  end

  def self.current_during_oe_text
    '[data-cuke="current-during-oe-text"]'
  end

  def self.current_not_during_oe_text
    '[data-cuke="current-not-during-oe-text"]'
  end

  def self.qhp_applicable_year_application_card
    '[data-cuke="applicable-year-application-card"]'
  end

  def self.qhp_applicable_draft_or_no_application_card
    '[data-cuke="applicable-year-draft-or-no-application-card"]'
  end

  def self.qhp_previous_year_application_card
    '[data-cuke="previous-year-application-card"]'
  end

  def self.qhp_previous_draft_or_no_application_card
    '[data-cuke="previous-year-draft-or-no-application-card"]'
  end

  def self.qhp_prospective_year_application_card
    '[data-cuke="prospective-year-application-card"]'
  end

  def self.qhp_prospective_draft_or_no_application_card
    '[data-cuke="prospective-year-draft-or-no-application-card"]'
  end

  def self.actions_dropdown
    ".interaction-click-control-actions"
  end
end
