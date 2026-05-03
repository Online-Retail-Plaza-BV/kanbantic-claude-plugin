---
description: "Prepare a Triaged Kanbantic issue until all readiness checks are green, then transition to Prepared (Triaged → Prepared, since plugin v2.2.0 / KBT-F235). Routes on issue.type: Feature → requirements + specs + test cases; Bug → root-cause + repro + regression test; Epic → sequential design + implementation plan. Does not create new issues. isReadyToClaim is now derived from Status == Prepared (single source of truth)."
disable-model-invocation: true
---

Invoke the kanbantic-issue-prepare skill and follow it exactly as presented to you
