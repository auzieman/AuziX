September 5, 2026 17:46 PDT — AX-012/task65

Operator: leftover `/bin/systemctl` is a bad path; we should have systemctl
or systemd. r7 Systemd archive already publishes Commands/systemctl and
Compatibility/bin/systemctl. Convert leftover `../bin/systemctl` to that
alias. Do not treat systemctl as a missing foreign manager. Local units
first. HDD locked. Kanboard task65 sync pending until posted.
