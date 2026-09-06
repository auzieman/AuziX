September 5, 2026 20:24 PDT — AX-012/task65

Operator: retry HDD. Same unlock-r11 image. Park failed a4e49aa4
hdd-runs and alpha-hdd dirs, then reuse
hdd_id=alpha-apk-20260905-alpha-unlock-r11 to VM 146.
Stager unlinks etc passwd/group/shadow/gshadow before cp so host cp
does not follow docker-export leaf links. Not VM145.
