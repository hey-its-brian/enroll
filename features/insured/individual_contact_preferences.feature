Feature: Insured Signup Contact Preferences page
    Background:
        Given bs4_consumer_flow feature is enabled
        And EnrollRegistry enroll_sms_notifications feature is enabled
        And EnrollRegistry contact_method_via_dropdown feature is disabled
        Given Individual has not signed up as an HBX user
        And Individual visits the Consumer portal during open enrollment
        When Individual creates a new HBX account via username
        Then Individual should see a successful sign up message
        And Individual sees Your Information page
        And the user registers as an individual

   Scenario: Individual lands on the Contact Preferences page
        And Individual clicks on the Continue button of the Account Setup page
        Then the Individual should see the Contact Preferences title
        And the Individual should see the contact explanation text
        And the Individual should see the contact fields
        And the Individual should see the Notices subtitle
        And the Individual should see the contact preferences fields
        And Email and Mail preferences should be checked
        And the Individual should see the language preferences field
        And the Individual should see the continue button

    Scenario: Individual submits form without required contact information
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        When the Individual submits the contact preferences form
        Then the Individual should see a generic alert "An email or mobile phone number is required."
        And the continue button should remain enabled

    Scenario: Individual submits form without selecting contact method
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a mobile phone number
        When the Individual submits the contact preferences form
        Then the Individual should see a generic alert "A contact method is required to proceed. If selecting Text, you must also choose Email or Mail."
        And the continue button should remain enabled

    Scenario: Individual selects text messaging without other contact methods
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a mobile phone number
        When the Individual selects text messaging as contact method
        And the Individual submits the contact preferences form
        Then the Individual should see a generic alert "Text cannot be your only contact method. If you select Text, you must also choose Email or Mail."
        And the continue button should remain enabled

    Scenario: Individual selects text messaging without mobile phone
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a home phone number
        When the Individual selects text messaging as contact method
        And the Individual submits the contact preferences form
        Then the Individual should see a validation message "You must enter a mobile phone number to receive notices and updates by text."
        And the continue button should remain enabled

    Scenario: Individual selects email contact method without email address
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a mobile phone number
        When the Individual selects email as contact method
        And the Individual submits the contact preferences form
        Then the Individual should see a validation message "You must enter an email address to receive notices and updates by email."
        And the continue button should remain enabled

    Scenario: Individual successfully submits with valid phone and email contact methods
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a mobile phone number
        And the Individual enters a personal email address
        When the Individual selects email as contact method
        And the Individual selects mail as contact method
        And the Individual submits the contact preferences form
        Then the Individual should proceed to the next step

    Scenario: Individual successfully submits with text messaging and other contact method
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a mobile phone number
        And the Individual enters a personal email address
        When the Individual selects text messaging as contact method
        When the Individual selects mail as contact method
        And the Individual submits the contact preferences form
        Then the Individual should proceed to the next step

    Scenario: Individual enters mobile phone with all zeros
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a mobile phone number with all zeros
        When the Individual selects text messaging as contact method
        And the Individual submits the contact preferences form
        Then the Individual should see a validation message "Mobile Phone number cannot be all zeros."
        And the continue button should remain enabled

    Scenario: Individual enters mobile phone beginning with zero
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a mobile phone number beginning with zero
        When the Individual selects text messaging as contact method
        And the Individual submits the contact preferences form
        Then the Individual should see a validation message "Phone numbers cannot begin with a 0. Please check the number you entered, remove any leading zeros, and resubmit."
        And the continue button should remain enabled

    Scenario: Individual enters home phone with all zeros
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a mobile phone number
        And the Individual enters a home phone number with all zeros
        And the Individual selects mail as contact method
        When the Individual submits the contact preferences form
        Then the Individual should see a validation message "Home Phone number cannot be all zeros."
        And the continue button should remain enabled

    Scenario: Individual enters home phone beginning with zero
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a mobile phone number
        And the Individual enters a home phone number beginning with zero
        And the Individual selects mail as contact method
        When the Individual submits the contact preferences form
        Then the Individual should see a validation message "Phone numbers cannot begin with a 0. Please check the number you entered, remove any leading zeros, and resubmit."
        And the continue button should remain enabled

    Scenario: Individual enters mobile phone that is too short
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a short mobile phone number
        When the Individual selects text messaging as contact method
        And the Individual submits the contact preferences form
        Then the Individual should see a validation message "You must enter a mobile phone number to receive notices and updates by text."
        And the continue button should remain enabled

    Scenario: Individual enters home phone that is too short
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a mobile phone number
        And the Individual enters a short home phone number
        And the Individual selects mail as contact method
        When the Individual submits the contact preferences form
        Then the Individual should see a validation message "Phone must be 10 digits long."
        And the continue button should remain enabled

    Scenario: Email preference requires home email field to be marked as required
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        When the Individual selects email as contact method
        Then the home email field should be marked as required

    Scenario: Text preference requires mobile phone field to be marked as required
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        When the Individual selects text messaging as contact method
        Then the mobile phone field should be marked as required

    Scenario: Both fields empty makes both fields required
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        Then the home email field should be marked as required
        And the mobile phone field should be marked as required

    Scenario: Mobile phone present but home email empty marks only mobile phone as required
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        When the Individual selects mail as contact method
        And the Individual enters a mobile phone number
        And the Individual unfocuses the current field
        Then the mobile phone field should be marked as required
        And the home email field should not be marked as required

    Scenario: Home email present but mobile phone empty marks only home email as required
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        When the Individual selects mail as contact method
        And the Individual enters a personal email address
        And the Individual unfocuses the current field
        Then the home email field should be marked as required
        And the mobile phone field should not be marked as required

    Scenario: Both fields present makes both fields required
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual enters a mobile phone number
        And the Individual enters a personal email address
        And the Individual unfocuses the current field
        Then the home email field should be marked as required
        And the mobile phone field should be marked as required

    Scenario: Mobile phone present with email preference selected requires both fields
        Given Individual clicks on the Continue button of the Account Setup page
        And the Individual clears the contact method checkboxes
        And the Individual enters a mobile phone number
        When the Individual selects email as contact method
        Then the home email field should be marked as required
        And the mobile phone field should be marked as required
