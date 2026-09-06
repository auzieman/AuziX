September 5, 2026 18:35 PDT — AX-012/task65 Blocked

HDD BKC a4e49aa4 failed rc=1. Host cp through absolute
/etc/passwd -> /System/Settings/passwd after docker export.
Work /var/lib/auzix-build/hdd-runs/alpha-apk-20260905-alpha-unlock-r11
and alpha-hdd/.../run.status=failed. VM145 untouched. VM146 not created.
Next: unlink etc passwd/group/shadow before cp in
stage-auzix-alpha-hdd-root.sh. Park failed dirs before same hdd_id retry.
Kanboard task65 sync pending until posted.

September 5, 2026 20:22 PDT — AX-012/task65 comment (sync pending)

Operator: prior HDD images already had sshd, passwd, users through E.
Read-only: VM145 and staged r20 /etc account files are regular files;
failed r11 export still has leaf links for passwd/group/shadow/gshadow.
Stager will materialize those four as regular files after Settings
edits. No new HDD until commit is on r730 and r11 dirs are parked.
