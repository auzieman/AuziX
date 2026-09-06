# Classic Linux runtime prefixes → AuziX variables.
# Lifecycle leftover scripts, grok path fields, and debian-intake text all apply
# this file. /usr /bin /lib Compatibility is rewrite-payload-paths.sed.
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
