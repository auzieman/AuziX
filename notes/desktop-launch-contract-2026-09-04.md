# Desktop launch contract — 2026-09-04

Validated against the VM145 alpha root after comparing desktop-visible errors
with package and session launchers.

- Enlightenment must receive `/System/Compatibility/usr/local/share` and
  `/System/Compatibility/usr/share` first in `XDG_DATA_DIRS`. Package-private
  data roots may follow them; otherwise Efreet sees incomplete application
  metadata and the menu appears empty.
- Desktop intake adapts only `argv[0]` to `/Programs/<Name>/current/Commands`.
  Distribution arguments such as LibreOffice's `--calc %U` remain intact.
- LibreOffice wrappers assemble the split program and UNO payload under the
  user's cache. That assembled `program` directory must precede
  `/System/Libraries` in `LD_LIBRARY_PATH`; otherwise origin-relative UNO
  registry lookup incorrectly requests `/System/Libraries/unorc` and
  `/System/Libraries/services.rdb`.
- The E session and rescue terminal export
  `SHELL=/System/Compatibility/bin/sh`; the rescue shell is interactive.
- The broad desktop-menu repair is diagnostic/manual. HDD composition relies
  on package-produced desktop entries and the shared XDG view rather than
  rewriting all launchers post-install.
- The HDD writer now rejects roots missing these session, LibreOffice, and
  desktop-entry contracts instead of emitting another regressed image.

The remaining LibreOffice process-lifetime issue was not declared solved by
this change. The path correction removes the captured UNO component-manager
failure, but GUI persistence still requires validation on the next staged root.
