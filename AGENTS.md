# AuziX working rules

## Record before acting

The operator requires a durable record BEFORE any code, package, container,
VM, image, service, or pipeline mutation. Chat memory is not the work ledger.
Read `notes/alpha-release-issues-2026-09-05.md` and the linked handoff before
continuing alpha work. Preserve unrelated user edits.

Before acting, create or update a repository issue note, BKC run, or Kanboard
item with: timestamp, issue ID, exact target, observed evidence, proposed change,
why it is necessary, execution method, rollback, and acceptance test. Unknown
facts remain unknown. Do not retrospectively present unrecorded work as planned.
After acting, record actual commands/script revision, outcome, artifact or log
location, remaining uncertainty, and next step. Include issue IDs in commits.

Use the existing BKC CLI/API/pipelines for lab execution and retained logs.
Builds and containers run on R730, never the laptop. Observe startup, then hand
off a monitoring command for long runs. No fabricated test passes: correct a
misordered test or explicitly record deferral and its release consequence.

Packages own tools and generic configuration; image/first-boot provisioning
owns deployment users, homes, group membership and user-specific access policy.
Preserve transitional links and known-good startup behavior. Confirm actual
payloads and live reference repairs before changing layout assumptions.

Live repairs do not close an issue: fold accepted fixes into their owner and
prove fresh-image behavior, including reboot where applicable. VM145's original
disk is the reference; preserve it unless explicitly authorized otherwise.

## Mandatory issue lifecycle

- Before implementation, select one AX issue and record its Kanboard task ID,
  starting evidence, action plan, rollback and test. No anonymous work.
- Move the selected task to Work in progress only when work actually starts.
- Move to Validating only after an identified fix/commit/artifact exists.
- Failed validation returns to Planning with the exact failure and next bounded
  check; use Blocked only for an actual external dependency. Do not hide failure.
- Done/Accepted requires the issue's acceptance evidence, including fresh-image
  and reboot proof where specified. A live patch or green unit test alone is not
  acceptance. Record deferred checks explicitly; never manufacture PASS.
- Keep repository action history and Kanboard comments linked by issue ID,
  commit and BKC run. Read back remote state after every transition.
- If Kanboard is unreachable, record the transition locally and mark remote
  sync pending before proceeding. Reconcile it when service returns.
- At handoff, state active issue, lifecycle state, evidence and next action.
  Review/Planning columns must not trigger infrastructure runs automatically.
