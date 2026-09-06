# Classic Linux prefixes → AuziX layout.
# Packaging (debian-intake RootFS text) and leftover intake/grok both apply this
# after package-owned RootFS rewrite. Keep the AuziX path; do not invent a helper.
# Longest prefixes first. Text/metadata only. Do not run against ELF.

s|/usr/local/lib/|/Libraries/Packages/|g
s|/usr/local/lib\>|/Libraries/Packages|g
s|/usr/libexec/|/System/Compatibility/usr/libexec/|g
s|/usr/libexec\>|/System/Compatibility/usr/libexec|g
s|/usr/local/share/|/System/Compatibility/usr/local/share/|g
s|/usr/local/share\>|/System/Compatibility/usr/local/share|g
s|/usr/local/bin/|/System/Compatibility/usr/local/bin/|g
s|/usr/local/bin\>|/System/Compatibility/usr/local/bin|g
s|/usr/share/|/System/Compatibility/usr/share/|g
s|/usr/share\>|/System/Compatibility/usr/share|g
# debconf/confmodule is Debian question protocol, not an AuziX file.
s|/System/Compatibility/usr/share/debconf/|/usr/share/debconf/|g
s|/System/Compatibility/usr/share/debconf\>|/usr/share/debconf|g
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
# Relative ../bin stays relative; do not invent Compatibility in the middle.
s|\.\./System/Compatibility/bin/|../bin/|g
s|\.\./System/Compatibility/sbin/|../sbin/|g
