# AX-012/task65 — leftover paths are where/when, not missing items

September 5, 2026 17:16 PDT. Operator: we have those objects. Debian
scripts still name donor coordinates and donor scriptlet time.

r6 leftover `/bin/dbus-daemon` is `/Programs/DBus/.../Commands/dbus-daemon`
plus Compatibility links. `pidof` at configure is the wrong moment;
`/Services` and first-boot start it. `update-initramfs` is the boot-media
builder, not a missing binary. `hwdb.bin`, sgml/xml catalogs, python3.13,
gzip `/bin`, and `ldconfig` are the same: shared layout or PATH, often
after another package or an apk trigger.

Do not apply payload `/usr*` sed before owned RootFS or debconf prune
(95000cc). Last leftover pass: donor `/usr` `/bin` `/lib` → shared
Compatibility/Libraries; command checks use PATH / `command -v` and
must not throw if the object is not here yet.

`/usr/share/debconf/confmodule` is not this family. It is Debian's
question protocol (`db_*`), not a file we keep under Compatibility.
The sed map restores that donor path after `/usr/share/` rewrite.
Unused import can still be pruned; a live `db_*` script stays `debconf`.

Not this family: debconf questions, `systemctl` as a binary, `adduser`.
Those are different kinds. HDD still locked.
