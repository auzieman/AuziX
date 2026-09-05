# Shared Debian → AuziX path translation.
# Longest prefixes first so `sed -f packaging/rewrite-paths.sed` is safe.
# Lifecycle applies this after package-owned RootFS rewrites.
# Text/metadata only. Do not run against ELF.

s|/usr/local/lib/|/Libraries/Packages/|g
s|/usr/local/lib\>|/Libraries/Packages|g
s|/usr/local/share/|/System/Compatibility/usr/local/share/|g
s|/usr/local/share\>|/System/Compatibility/usr/local/share|g
s|/usr/local/bin/|/System/Compatibility/usr/local/bin/|g
s|/usr/local/bin\>|/System/Compatibility/usr/local/bin|g
s|/usr/share/|/System/Compatibility/usr/share/|g
s|/usr/share\>|/System/Compatibility/usr/share|g
s|/usr/sbin/|/System/Compatibility/sbin/|g
s|/usr/sbin\>|/System/Compatibility/sbin|g
s|/usr/bin/|/System/Compatibility/bin/|g
s|/usr/bin\>|/System/Compatibility/bin|g
s|/usr/lib/|/Libraries/|g
s|/usr/lib\>|/Libraries|g
s|/var/cache/|${AUZIX_CACHE}/|g
s|/var/cache\>|${AUZIX_CACHE}|g
s|/var/spool/|${AUZIX_STATE}/spool/|g
s|/var/spool\>|${AUZIX_STATE}/spool|g
s|/var/run/|${AUZIX_RUN}/|g
s|/var/run\>|${AUZIX_RUN}|g
s|/var/lock/|${AUZIX_RUN}/lock/|g
s|/var/lock\>|${AUZIX_RUN}/lock|g
s|/var/lib/|${AUZIX_STATE}/|g
s|/var/lib\>|${AUZIX_STATE}|g
s|/var/log/|${AUZIX_LOGS}/|g
s|/var/log\>|${AUZIX_LOGS}|g
s|/lib64/|/Libraries/|g
s|/lib64\>|/Libraries|g
s|/lib/|/Libraries/|g
s|/lib\>|/Libraries|g
s|/bin/|/System/Compatibility/bin/|g
s|/bin\>|/System/Compatibility/bin|g
s|/sbin/|/System/Compatibility/sbin/|g
s|/sbin\>|/System/Compatibility/sbin|g
s|/etc/|${AUZIX_SETTINGS}/|g
s|/etc\>|${AUZIX_SETTINGS}|g
s|/run/|${AUZIX_RUN}/|g
s|/run\>|${AUZIX_RUN}|g
s|/tmp/|${AUZIX_TMP}/|g
s|/tmp\>|${AUZIX_TMP}|g
s|/root/|${AUZIX_ROOT_USER}/|g
s|/root\>|${AUZIX_ROOT_USER}|g
s|/var/|${AUZIX_STATE}/|g
s|/var\>|${AUZIX_STATE}|g
