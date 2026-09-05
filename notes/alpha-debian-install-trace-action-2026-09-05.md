# AX-012/task65 — observe Debian installation, not synthetic hooks

September 5, 2026, before execution. User explicitly requests examination of
why Debian works. Run a disposable existing debian:trixie-slim container on
R730 through the committed BKC source-audit lane. No AuziX repair is attempted.
Capture baseline inventory, APT dependency plan, dpkg maintainer-script debug
trace, resulting inventory/account/permissions, installed control scripts and
trigger declarations. Request D-Bus 1.16.2-2, the exact reviewed source version;
do not silently substitute another version if unavailable.

Compare actual configuration order to source dbus-system-bus-common.postinst
and dbus.postinst. Observe service-start policy in the container honestly.
Separately start the installed daemon and make a real system-bus method call;
this is runtime proof, not evidence that package installation auto-started it.
Retain all logs in a new source-addressed audit directory. No host APT changes,
compilation, VM repair, package promotion or image build. Rollback is automatic
disposal of the container; retained prior evidence remains untouched.
Acceptance: actual successful dpkg transaction and traced script invocations,
account provider order, root:messagebus 4754 and bus reply, or exact failure.
