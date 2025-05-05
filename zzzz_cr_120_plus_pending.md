### Pending Items/Questions
  - Code Management - Angus
    - A potential long standing development branch as we have to make changes to the existing models.
  - We might have to put our system in maintenance mode for **A DAY or TWO** because of the data migration. - Sarah B
  - What all projects out of 120, 122, 123, 47, and 42 we are delivering before Open Enrollment? '120, 122, and 123'

### Dev TODOs
  - Update Data Warehouse team once the contact preferences models are finalized.
  - More aasm_states/current_states for QHP Application. An application can be in draft, cancelled,  errored_during_submission, submitted (waiting for preliminary determination), preliminary_determined, finalized (all the eligible verifications are either in verified or rop_expired)
  - Create release notes to include the following:
    - Feature Flag
    - All the Indexes that needs to be created
    - All the data migrations and their detailed execution steps

### Data Migration
  - As part of the migration we will do the below:
    - Create a new FAA application for all the families with a 2025 FAA determined application with the below information:
      - Evidences Migration: This application has all the verification_types and evidences_1.0 as evidences_3.0
      - Application state info: aasm_state as :determined, origin_source as :migration, and generation_reason as :manual
      - Determination Result: This application should have the same determination result as the most recently (by submitted_at timestamp) determined application
    - For all the remaining families, create a new QHP application with the below information:
      - Evidences Migration: This application has all the verification_types as evidences_3.0
      - Application state info: aasm_state as :determined, origin_source as :migration, and generation_reason as :manual
      - Determination Result: Determination should be created by running the QHP determination rules.
    - Ensure all the operations that
