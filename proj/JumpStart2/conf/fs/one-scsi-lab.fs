disk_config sda
primary   /           8192        defaults,errors=remount-ro
primary   swap        256         pri=0
primary   /export/crawlspace      10-        rw ; lazyformat -i 65536 -m 1
