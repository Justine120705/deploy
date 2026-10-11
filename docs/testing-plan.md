# Software Testing Plan (clearance path)

Pulled forward from Sprint 4 for the clearance slice (GitHub issue #69, Sprint 3 plan item S3-11). SDLC section 7.7.
Every result below was recorded when the test ran. Nothing is copied from the expected column.

## 1. Scope and objectives

In scope: the live clearance path of the Cabuyao University portal, from the student's request to the Registrar's
final clearance, and the audit trail, with the access rules that protect it.

| Area | Requirements |
| --- | --- |
| Student requests clearance, sees every office | REQ-STU-03, REQ-STU-06 |
| Department lifts holds and approves | REQ-DPT-01, REQ-DPT-02, REQ-DPT-03 |
| Cashier logs payments and tags charges; Finance clears automatically | REQ-CSH-01, REQ-CSH-02, REQ-CSH-03 |
| Registrar issues final clearance only when every office has cleared | REQ-REG-03 |
| Admin reads the audit log, read-only | REQ-ADM-03 |
| Isolation between students, roles and anonymous users | ETH-01, SEC-02 |

Out of scope in Sprint 3 (still mock data, labelled "Sample data" in the app): grades, enrollment, document requests,
the Registrar's grades, enrollments and documents screens, Admin users and academic setup. Not done: SEC-03 login
lockout, SEC-04 rate limiting, a deployed (Vercel) run, phone-width and dark-mode scans for every role, CSV export in
the browser.

## 2. Test levels

| Level | What | Where |
| --- | --- | --- |
| Database (SQL) | grants, RLS, triggers, views, audit log; each case runs in a rolled-back transaction | `docs/database/*_test.sql`, `docs/issue-12-testing-guide.md` (TC-01 to TC-70), this file (TC-71) |
| End to end (browser) | the whole chain through the real screens with the seeded accounts | section 5 |
| Static checks | `npx tsc --noEmit`, `npx eslint app components lib types`, `npm run build` | before every pull request |

## 3. Accounts

Test accounts live in Supabase Auth (created by the Project Manager; passwords are never in the repo or in chat).

| Role | Account | Person in the data |
| --- | --- | --- |
| Admin | admin@pnc.test | |
| Registrar | registrar@pnc.test | Cruz, Rey |
| Cashier | cashier@pnc.test | Diaz, Cora |
| Department (College of Computer Studies) | dept@pnc.test | Tan, Hal |
| Student 1 | student1@pnc.test | Reyes, Ana (2026-0001, BSCS) |
| Student 2 | student2@pnc.test | Santos, Ben (2026-0002, BSIT) |
| Student 3 | student3@pnc.test | Mendoza, Carla (2026-0003, BSBA) |

The College of Business Administration and the College of Arts and Sciences have no staff accounts in the seed, so their
clearance items can only be cleared by SQL as the database owner (recorded as test setup where it was used).

## 4. Environment and how results are recorded

- Database: the Supabase project `sv-student-portal` (labelled production), Data API with column-level grants, the
  triggers of issues 22 to 24 live.
- Application: Next.js 16 dev server on `http://localhost:3000`, the Claude desktop app's browser pane.
- Who runs what: the Project Manager signs in to each account in the browser pane and pastes and runs SQL in the
  Supabase SQL editor; Claude drives the pages, reads the result row or the page text, and records it here.
- Each case lists: the steps, the expected result, the actual result with the date, and Pass or Fail. A failure is filed
  as a GitHub issue and stays in this file.
- SQL cases end with `rollback;` or use throwaway data; the browser walk in section 5 changed the seed data on
  2026-10-11 (see section 7).

## 5. End-to-end test: the clearance chain (browser, 2026-10-11)

Subject: Santos, Ben (student2). Start state: clearance 2 for 1st 2026-2027 with 0 of 4 offices cleared, an active
CCS hold ("Missing lab equipment"), one unpaid charge of 15,000.

| ID | Role and steps | Expected | Actual (2026-10-11) | Result |
| --- | --- | --- | --- | --- |
| E2E-01 | Student requests clearance. With a throwaway current term (2098-2099, removed afterwards) student2 and student1 each clicked "Request clearance" | A clearance with one item per office is created; a notice confirms it | Clearance created with 4 pending items each; notice "Clearance requested. Each office will now review it." The trigger created the items. | Pass |
| E2E-02 | Student requests a second time (stale second tab) | One clearance per student per term; a clear message; no second row | Notice "You already requested clearance for this term..." and the existing clearance; no second clearance (first attempt showed no message: defect fixed in the same pull request, see section 7) | Pass |
| E2E-03 | Department: open Clearance Items with Ben's hold active | Ben's Approve is blocked with a reason | Approve disabled; text "Approval is blocked. Lift the active hold first." | Pass |
| E2E-04 | Department: lift Ben's hold | Hold shows lifted, by whom and when; active holds 0 | "Hold lifted for Santos, Ben. You can approve the item now."; lifted Oct 11, 2026 by Tan, Hal (you); active holds 0 | Pass |
| E2E-05 | Department: approve Ben's CCS item | Item cleared with the server date | "Approved for Santos, Ben."; Ben moved to Decided, cleared Oct 11, 2026; department cleared count 1 to 2 | Pass |
| E2E-06 | Cashier: log a payment with an existing receipt number (OR-0001) | Refused with a clear message; nothing written | "This receipt number is already used. Use a new one."; payments still 2, collected 20,000 | Pass |
| E2E-07 | Cashier: log Ben's 15,000 under OR-0003 | Payment recorded with the server date; balance 0 | "Logged 15,000 as receipt OR-0003."; payments 3, collected 35,000, date Oct 11, 2026 | Pass |
| E2E-08 | Cashier: tag Ben's charge Cleared | Charge Cleared; Finance item clears by itself | "Charge marked Cleared..."; on Finance Clearance Ben's item Cleared with no manual step, finance items cleared 1 to 2, outstanding 25,000 to 10,000 | Pass |
| E2E-09 | Setup (SQL, owner): clear Ben's College of Business Administration and Arts and Sciences items (no staff accounts exist for those offices) | 2 rows updated | 2 rows (items 7 and 8 of clearance 2) | Setup |
| E2E-10 | Registrar: select Carla's request (0 of 4) | Final clearance button disabled with a visible reason | Disabled; "...offices have not cleared yet: Cashier's Office, College of Computer Studies, College of Business Administration, College of Arts and Sciences." | Pass |
| E2E-11 | Registrar: select Ben's request (4 of 4) and issue final clearance | Button enabled; clearance approved with the approver and date | "Santos, Ben has cleared every office. Final clearance can be issued." then "Final clearance issued."; 4 of 4, Approved, "approved by Cruz, Rey on Oct 11, 2026"; Issued count 1 | Pass |
| E2E-12 | Student 2: open the clearance page and dashboard | Everything cleared and approved | 4 of 4 cleared, "Registrar final approval: Approved", "Your clearance is complete."; dashboard agrees but still shows the old hint line (finding F-1) | Pass, with finding F-1 |
| E2E-13 | Admin: open the audit log | Every step above is present with the actor | Hold lifted and CCS item cleared (Hal Tan, 22:45), payment OR-0003 and charge Cleared and Finance item cleared (Cora Diaz, 22:47), items 7 and 8 (System, the setup SQL), clearance approved (Rey Cruz, 22:49); the refused duplicate receipt left no row; 31 entries | Pass |

## 6. Negative and isolation cases

| ID | Case | Expected | Actual | Result |
| --- | --- | --- | --- | --- |
| N-01 | Student A cannot see student B (browser) | Each student sees only their own clearance | Student 1: 2 of 4, no hold. Student 2: 0 of 4 with the CCS hold. None of the other's items appeared (2026-10-11) | Pass |
| N-02 | Student 1 reads student 2's data (SQL, TC-12 to TC-14, TC-30) | 0 rows | All 0; views show own rows only (2026-10-10, again 2026-10-11 after the grants and each trigger) | Pass |
| N-03 | A department cannot read or approve another department's item (SQL, TC-71, `docs/database/e2e_negative_tests.sql`) | 0 other items visible; approve changes 0 rows; item stays pending | other_items_visible 0; dept_approves_other_office "rows 0"; still_pending true; "-> OK" (2026-10-11) | Pass |
| N-04 | Approval with an active hold fails (SQL, TC-42, TC-45, TC-47) | Error "active hold: ..."; no audit row | Blocked for the Department user and for postgres; the Cashier's Financial item ignores a Department hold and is blocked by a Financial hold (2026-10-11, live) | Pass |
| N-05 | Final clearance with a pending item fails (SQL, TC-63, TC-64, TC-67; UI E2E-10) | Error "pending items: ..."; the Financial item alone also blocks | Blocked for the Registrar and postgres; a clearance with no items is also refused (2026-10-11, live) | Pass |
| N-06 | Non-Registrar roles cannot approve a clearance (SQL, TC-66, TC-39) | 0 rows | Student, Cashier and Department: rows 0 | Pass |
| N-07 | Anonymous has no access to any exposed object (SQL, TC-35, TC-33, TC-16) | Permission denied | 19 of 19 anon statements and all 4 views denied (2026-10-11, live) | Pass |
| N-08 | The audit log cannot be changed (SQL, TC-25) | UPDATE, DELETE and TRUNCATE blocked, even as postgres | All three blocked (2026-10-11 regression) | Pass |
| N-09 | Routing: a role cannot open another role's module (TC-03 to TC-10) | Redirect to the role's home | All redirect (2026-10-10, localhost) | Pass |

## 7. Findings and deviations

| ID | Finding | Status |
| --- | --- | --- |
| F-1 | The student dashboard clearance card still shows "After all 4 offices clear you, the Registrar gives the final approval." after the clearance is approved (found in E2E-12) | Fixed (GitHub issue #83): the hint now shows only while an office is still pending. Retested 2026-10-11 in the browser: student2 (approved) no longer shows it, student1 (2 of 4) still does |
| F-2 | The duplicate-request message was lost on first test because the page re-rendered to the clearance view | Fixed before merge (notice after redirect), retested E2E-02 |
| F-3 | TC-68 and TC-69 expectations assumed a lone `approved_at` or `approved_by` could be saved; table check `ck_clearances_approval` requires both together | Test expectations corrected; the trigger behaved as designed |
| F-4 | First rehearsal of issue 23 stopped at its own safety check (a varchar type comparison) | Check fixed; rehearsal then passed |
| D-1 | The browser walk changed the seed data on 2026-10-11: Ben's hold is lifted, his charge is Cleared, a 15,000 payment OR-0003 exists, all four of his items are cleared and his clearance is approved. The audit rows stay (append-only). Resetting needs SQL by the owner | Recorded; reset only if a fresh demo is needed |
| D-2 | Two of the four offices have no staff account, so E2E-09 used SQL | Recorded as setup |

## 8. Database suites (details in `docs/issue-12-testing-guide.md`)

| Suite | Cases | Last run | Result |
| --- | --- | --- | --- |
| Routing (browser) | TC-01 to TC-11 | 2026-10-10 | Pass |
| Isolation, hardening, views, regression | TC-12 to TC-33 | 2026-10-11 (after every change; 22 results identical each time) | Pass |
| Grants for the clearance slice | TC-34 to TC-40 | 2026-10-11 (live; TC-40 through the app) | Pass |
| Trigger: no approval with an active hold | TC-41 to TC-48 | 2026-10-11 (live) | Pass |
| Trigger: Finance clears automatically | TC-49 to TC-61 | 2026-10-11 (live) | Pass |
| Trigger: final clearance needs every item | TC-62 to TC-70 | 2026-10-11 (live) | Pass |
| Negative case: another department's item | TC-71 | 2026-10-11 | Pass |

## 9. How to re-run

1. Database cases: paste the file named in the table into the Supabase SQL editor, as postgres, one tab per file, and run
   the whole tab (each ends in `rollback;`). The regression is one paste: `docs/database/regression_after_grants.sql`.
2. Browser walk: sign in to each account in the browser pane in the order of section 5; use the throwaway-term
   steps of E2E-01 if no student without a clearance exists.
3. Before a pull request: `npx tsc --noEmit`, `npx eslint app components lib types`, `npm run build`.
