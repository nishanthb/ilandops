#!/bin/sh

id tops >/dev/null 2>&1  || useradd tops -u 1100 -G users -g users
