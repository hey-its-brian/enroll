# frozen_string_literal: true

# Helper for "resource registry features"
module ResourceRegistryHelper
  def qhp_application_feature_enabled?
    EnrollRegistry.feature_enabled?(:qhp_application)
  end
end
