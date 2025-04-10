### Pending Items/Questions
  - Code Management - Angus
    - A potential long standing development branch as we have to make changes to the existing models.
  - We might have to put our system in maintenance mode for **A DAY or TWO** because of the data migration. - Sarah B

### Dev TODOs
  - Include Preferences estimates into the actual estimates on the spreadsheet.
  - Do we need separate models for work_email and personal_email? They both have one single field each.
  - Cache the Open Enrollment information. We query the OE information on most of the pages and places in the codebase.
  - At a time we can only have one editable application per assistance year per application type. We need to expire the previos draft as soon as a new application is created. This applies for all aasm states (draft, submitted, determined, etc).
  - Add is_renewal flag to the application. This will be used to determine if the application is a renewal or not. This will be used in the application workflow and in the application model.
  - Review origin_source and generation_reason fields of application model.
  - Research to see if we cannot generate hbx_id for applicant and depend on person's hbx_id. This will be a change that is required to not update person hbx_id. Currently, we are updating person hbx_id in some cases after person already has hbx_id. We can generate a new id for applicant for communicating with MitC.