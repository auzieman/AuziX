AX-012 / twelve-ticket pilot — September5 — before implementation

R10 completed, image8382adbe5211898e6d1d1b4df813fdee16f7b881e85fd67409b35f4296c7a186.
Preserve it. Scoped first repackaging pass addresses confirmed shared loss:
automatic library adapters currently replace donor scripts/configuration with
empty lists. Make automatic publication additive, preserving normalized donor
steps and unresolved findings. Recover physically retained control files absent
from old receipt annotations; do not infer scriptlessness from that omission.
Retain original donor control material/provenance in the promoted package.
Clarify conversion-only log labels. Test preservation and failure cases.

Execution: commit source, then BKC fresh pilot conversion using R10 selected
archives in a separate output, not an image rebuild or R10 repository mutation.
Any revealed unmapped donor effects remain review failures; no blanket adapter
acceptance. Twelve plans remain the scope/acceptance ledger. This pass does not
claim to finish every runtime/profile/provisioning item. Rollback is scoped
source revert; keep old artifacts and all proof files. No direct SSH repair.

Execution detail: reuse R10's 117 selected archives and pinned factory image,
mount current committed Python/packaging read-only, and emit into a fresh
AX-012 proof directory. No compilation, repository refresh or image deployment.
Add a named BKC conversion-only lane and a generic issue state option to the
existing Kanboard helper; task65 moves to WIP, then validation or Blocked based
on recorded results. Local regression suite: 68 tests passed before lane setup.

Pilot r1 / BKC bf59fcdb-70c5-48c0-acc6-93a429f2991d failed before conversion:
the pipeline exports source with git archive; proof script incorrectly expected
a .git checkout for provenance. Correct only provenance capture to use required
AUZIX_SOURCE_REF already supplied by BKC. Preserve the r1 proof directory; rerun
with the new commit/output. No package conversion occurred in r1.
