# frozen_string_literal: true

# Helper for "race and ethnicity selections
# This module provides methods to generate collections"
module RaceAndEthnicityHelper
  def ethnicity_collection
    [
      ["White", "Black or African American", "Asian Indian", "Chinese"],
      ["Filipino", "Japanese", "Korean", "Vietnamese", "Other Asian"],
      ["Native Hawaiian", "Samoan", "Guamanian or Chamorro"],
      ["Other Pacific Islander", "American Indian/Alaska Native", "Other"]
    ].inject([]) do |sets, ethnicities|
      sets << ethnicities.map{|e| OpenStruct.new({name: e, value: e})}
    end
  end

  def latino_collection
    [
      ["Mexican", "Mexican American"],
      ["Chicano/a", "Puerto Rican"],
      ["Cuban", "Other"]
    ].inject([]) do |sets, ethnicities|
      sets << ethnicities.map{|e| OpenStruct.new({name: e, value: e})}
    end
  end
end
