# Sprint 3: plan and what was delivered

Sprint 3 was planned for Oct 6 to Oct 8 and was compressed to one day, Oct 11, 2026, with the final deadline on Oct 12.
The Project Manager chose the scope: ONE live end-to-end clearance path; everything else stays on mock data and is
labelled "Sample data" in the app. (The original plan PDF is held by the Project Manager and is not in the repository.
The plan items below use the numbers S3-1 to S3-12 and the GitHub issues #60 to #70, titled "Issue 21" to "Issue 31".)

## Plan versus delivered

| Item | GitHub issue | Delivered | Evidence |
| --- | --- | --- | --- |
| S3-1 Expose the clearance slice in the Data API with least-privilege grants (SEC-02) | #60, PR #73, #74 | Yes, run live 2026-10-11 | `docs/database/grants_clearance.sql`, TC-34 to TC-40 |
| S3-2 Trigger: department approval requires no active hold (REQ-DPT-03) | #61, PR #75 | Yes, live | `trigger_dept_approval.sql`, TC-41 to TC-48 |
| S3-3 Trigger: the Finance item clears automatically (REQ-CSH-03) | #62, PR #76 | Yes, live | `trigger_finance_autoclear.sql`, TC-49 to TC-61 |
| S3-4 Trigger: final clearance requires every item cleared (REQ-REG-03) | #63, PR #77 | Yes, live | `trigger_final_clearance.sql`, TC-62 to TC-70 |
| S3-5, S3-6 Student clearance on live data and the request button (REQ-STU-03, REQ-STU-06) | #64, PR #78 | Yes | request, duplicate and isolation tested in the browser |
| S3-7 Department items and holds on live data | #65, PR #79 | Yes | testing plan E2E-03 to E2E-05 |
| S3-8 Cashier balances, payments, charge tagging | #66, PR #80 | Yes | E2E-06 to E2E-08 |
| S3-9 Registrar clearance and final clearance | #67, PR #81 | Yes | E2E-10, E2E-11 |
| S3-10 Admin audit log | #68, PR #82 | Yes | E2E-13 |
| S3-11 End-to-end test and testing plan | #69, PR #84 | Yes | `docs/testing-plan.md` |
| S3-12 Documentation and sample-data labels | #70 | Yes, this change | Revision Log row 11, SDLC 6 and 7.3, this file |

Beyond the plan: a one-paste regression script (`regression_after_grants.sql`, TC-12 to TC-33) that was re-run after every
database change, a negative end-to-end case (TC-71), and a rule added in the Cashier screens (a charge can be tagged
Cleared only when fully paid; a payment cannot exceed the balance).

## Carried over (still mock data, labelled "Sample data")

| Requirement | What is not live |
| --- | --- |
| REQ-REG-01 | Registrar grade encoding |
| REQ-REG-02, REQ-DOC-01, REQ-DOC-02, REQ-STU-04 | Document requests and tickets (Registrar queue and the student's requests) |
| REQ-REG-04, REQ-STU-05 | Enrollment review and the student's online enrollment |
| REQ-STU-02 | Student grades and enrollment status |
| REQ-ADM-01 | Admin user accounts (create, update, deactivate) |
| REQ-ADM-04 | Admin academic catalog |

Not done: SEC-03 (login lockout, still a TODO in `app/(auth)/login/actions.ts`) and SEC-04 (rate limiting).
Also not done or not confirmed: a Vercel deployment check, phone-width and dark-mode scans for every role, CSV export
in the browser, and a teammate review of the pull requests.

Every screen that reads mock data shows the shared "Sample data" note (`components/ui/SampleDataNote.tsx`): the
student dashboard sections and the grades, enrollment and documents pages; the Registrar dashboard sections and the
grades, enrollments and documents pages; the Admin dashboard, users and academic setup pages.

## Sprint 2 retrospective notes

Recorded for Issue 18 ("Sprint 2 retrospective and Sprint 3 planning", GitHub #25).

Keep
- One SQL file per database change, with a rollback block and diagnostics, tested in a transaction that ends in
  `rollback;` before the Project Manager runs it. In Sprint 3 the rehearsals and the first live test runs caught four
  defects early, each fixed before it mattered (a wrong type comparison in a safety check, two tests that assumed a
  table could save a lone approval column, a test that picked data the new rule correctly refused, and a cleanup
  statement in the wrong order for the one-current-term rule).
- One paste, one result row, "-> OK" or "-> FAIL" in each cell: fast to run and unambiguous to read.
- Building the database rules first and the screens after: the screens needed no workarounds.
- Writing every result down with its date and who ran it.

Change
- Sprint 2 ended five days late (Oct 5 became Oct 10) and Sprint 3 shrank to one day. Plan fewer modules per sprint and
  finish one slice end to end before starting the next.
- Keep the documents and the code in step: the documents said "Pamantasan ng Cabuyao" while the app says "Cabuyao
  University", and the design notes in `docs/design` describe an older design.
- Seed data should include an office with staff accounts for every department, so the whole chain can be walked
  without SQL (two offices had no staff account in the end-to-end test), and a student with no clearance, so the
  request step can be demonstrated.
- Test the write paths earlier: the first browser run of the request button found a missing message that no SQL test
  could have found.
- Get a teammate review on every pull request; none has been done yet.
