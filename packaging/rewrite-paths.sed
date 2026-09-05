# Layer 2: shared runtime leftovers after package-owned RootFS rewrite.
# Lifecycle and debian-intake both apply this file.
# /usr* payload Compatibility is packaging/rewrite-payload-paths.sed.
# Longest prefixes first so `sed -f` is safe. Text/metadata only. Do not run against ELF.

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
