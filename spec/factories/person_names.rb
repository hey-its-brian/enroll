# frozen_string_literal: true

FactoryBot.define do
  factory :person_name do
    given_name { 'Johnny' }
    middle_name { 'A.' }
    family_name { 'Doe' }
    name_sfx { 'Jr.' }
    name_pfx { 'Mr.' }
    alternate_name { 'John' }
  end
end
