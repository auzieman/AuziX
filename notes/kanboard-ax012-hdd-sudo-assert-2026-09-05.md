September 5, 2026 20:47 PDT — AX-012/task65

BKC cce7464a not hung; failed rc=1 after publishing Sudo current.
Builder test -x followed /Programs/Sudo/host on r730. Next: assert the
staged host binary and chroot current. Then park and retry same hdd_id
to VM 146. Not VM145.
