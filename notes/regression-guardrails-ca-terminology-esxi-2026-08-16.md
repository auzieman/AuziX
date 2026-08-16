# Regression guardrails — CA, Terminology, ESXi ISO boot

The recent failures were not new mysteries. They were regressions of already
working areas:

- Terminology launch/runtime drifted after package rebuilds.
- CA certificates drifted because the package staged the trust store under
  `/System/Compatibility/etc/ssl`, while some generated wrappers/defaults
  pointed at `/etc/ssl`. Since `/etc` maps to `/System/Settings`, that requires
  `/System/Settings/ssl` to alias the compatibility SSL tree.
- ESXi ISO boot drifted because direct shell knowledge was not folded into the
  BKC lane soon enough.

## Standing rule

Do not hand-fix these live first. Fix the package/build contract and add a
validation check so the same class of regression fails before ISO promotion.

## CA cert contract

Canonical AUZiX values:

```sh
SSL_CERT_DIR=/System/Compatibility/etc/ssl/certs
SSL_CERT_FILE=/System/Compatibility/etc/ssl/certs/ca-certificates.crt
CURL_CA_BUNDLE=$SSL_CERT_FILE
REQUESTS_CA_BUNDLE=$SSL_CERT_FILE
```

Compatibility alias required for hardwired `/etc/ssl` callers:

```text
/System/Settings/ssl -> /System/Compatibility/etc/ssl
```

`scripts/validate-auzix-live-agent.sh` must fail if either the canonical bundle
or this alias is missing.

## Terminology contract

Terminology wrappers should source `/System/Settings/auzix-paths.sh` and then
inherit the canonical CA and library paths. Wrapper-local fallbacks must use the
AUZiX paths, not stale `/etc/ssl` defaults.

## ESXi ISO boot contract

ESXi boot smoke belongs in BKC. The helper must validate the CD-ROM backing and
serial evidence as part of the pipeline run. The known good BKC run is:

```text
28dcf92d-89a9-46ca-bdc3-c367aa75a176
```

Future work should extend that lane rather than re-learning ESXi media attach
from shell history.
