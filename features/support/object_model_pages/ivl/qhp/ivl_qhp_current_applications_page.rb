# frozen_string_literal: true

#qhp current applications page
class IvlQhpCurrentApplicationsPage

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
