# Peer Review Checklist

Please ensure the following are verified during the peer review process:

1. Verify the title follows the [guidelines](https://github.com/ideacrew/enroll/blob/trunk/CONTRIBUTING.md#commit).
2. Verify that the PR type, ticket number, and a brief description of the changes are included.
3. Verify the feature flag section is included for new feature development.
4. Ensure that for all scripts or rake tasks, how to run them is documented in both the PR and the code.
5. Ensure there is Cucumber coverage for all UI changes.
6. Confirm there are no inline styles added.
7. Confirm there is no inline JavaScript added.
8. Verify there is no hard-coded text added/updated in helpers/views/JavaScript.
9. Ensure new/updated translation strings do not include markup/styles unless there is supporting documentation.
10. Verify that all images added/updated have alt text.
11. Confirm that tests for the changes have been added and they use `let` helpers and `before` blocks.
12. Verify that any endpoint modified in the PR only responds to the expected MIME types.
13. Check that any endpoint touched in the PR has an appropriate Pundit policy. For open endpoints, verify that the reasoning is documented in the PR and code.
14. Ensure the code does not use `.html_safe`.
15. Confirm that the code does not bypass RuboCop rules in any way.