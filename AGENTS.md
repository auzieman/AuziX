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
