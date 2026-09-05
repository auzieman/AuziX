# Layer 3: Debian payload text only (desktop/service/script files in RootFS).
# Do not apply this in lifecycle leftover mapping. Unowned /usr/bin stays a finding.
# Longest prefixes first. Text/metadata only. Do not run against ELF.

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
s|/lib64/|/Libraries/|g
s|/lib64\>|/Libraries|g
s|/lib/|/Libraries/|g
s|/lib\>|/Libraries|g
s|/bin/|/System/Compatibility/bin/|g
s|/bin\>|/System/Compatibility/bin|g
s|/sbin/|/System/Compatibility/sbin/|g
s|/sbin\>|/System/Compatibility/sbin|g
