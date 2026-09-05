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
At minimum, anything that alters the lab environment (packages, containers,
images, VMs, services, factory proof directories, R730/PVE runs) goes through
`bkc-cli` so it leaves a paper trail: run id, command, logs, and receipt.
Read-only SSH inspection is allowed. Do not launch mutating worker scripts,
docker runs, or image/HDD builds by raw SSH, even when a pipeline script
already exists. Builds and containers run on R730, never the laptop. Observe
startup, then hand off a monitoring command for long runs. No fabricated test
passes: correct a misordered test or explicitly record deferral and its
release consequence.

Packages own tools and generic configuration; image/first-boot provisioning
owns deployment users, homes, group membership and user-specific access policy.
Preserve transitional links and known-good startup behavior. Confirm actual
payloads and live reference repairs before changing layout assumptions.

Live repairs do not close an issue: fold accepted fixes into their owner and
prove fresh-image behavior, including reboot where applicable. VM145's original
disk is the reference; preserve it unless explicitly authorized otherwise.

## Mandatory issue lifecycle

If we find or fix something, it goes on a ticket. New evidence is a dated
comment (or a new AX card when no owner exists). Fixes attach to that card:
plan, commit, BKC run, and result. Chat is not the ledger.

- Ticket descriptions hold scope and acceptance criteria. Progress, failures,
  decisions, commits and run results are dated comments, not description rewrites.
  Attach relevant screenshots/log excerpts/receipts; preserve existing evidence.
  Read back updates and deduplicate retries. Description edits are intentional
  scope corrections only, never a side effect of routine synchronization.

- Before implementation, select one AX issue and record its Kanboard task ID,
  starting evidence, action plan, rollback and test. No anonymous work.
- Move the selected task to Work in progress only when work actually starts.
- Move to Validating only after an identified fix/commit/artifact exists.
- Failed validation moves to Blocked with the exact failure, next bounded check
  and unblock criteria in a comment. Planning is not a failure state. Rejected
  is for an explicitly rejected approach/artifact, not a recoverable dependency
  gap. Do not hide failures or create new board columns without agreement.
- Done/Accepted requires the issue's acceptance evidence, including fresh-image
  and reboot proof where specified. A live patch or green unit test alone is not
  acceptance. Record deferred checks explicitly; never manufacture PASS.
- Keep repository action history and Kanboard comments linked by issue ID,
  commit and BKC run. Read back remote state after every transition.
- If Kanboard is unreachable, record the transition locally and mark remote
  sync pending before proceeding. Reconcile it when service returns.
- At handoff, state active issue, lifecycle state, evidence and next action.
  Review/Planning columns must not trigger infrastructure runs automatically.
