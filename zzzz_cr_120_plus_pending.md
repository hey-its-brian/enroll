### Pending Items/Questions
  - Code Management - Angus
    - A potential long standing development branch as we have to make changes to the existing models.
  - We might have to put our system in maintenance mode for **A DAY or TWO** because of the data migration. - Sarah B

### Dev TODOs
  - Include Preferences estimates into the actual estimates on the spreadsheet.
  - Do we need separate models for work_email and personal_email? They both have one single field each.
  - Cache the Open Enrollment information. We query the OE information on most of the pages and places in the codebase.
  - At a time we can only have one editable application per assistance year per application type. We need to expire the previos draft as soon as a new application is created. This applies for all aasm states (draft, submitted, determined, etc).
