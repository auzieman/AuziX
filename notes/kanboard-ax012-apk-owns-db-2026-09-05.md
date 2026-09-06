September 5, 2026 17:39 PDT — AX-012/task65

Debian maintainer scripts exist because dpkg has a database. apk has
its own. Do not ship Dpkg/Debconf so those scripts can run. Adapted
means apk scriptlet, trigger, owned path. Luggage is not an alternate.
