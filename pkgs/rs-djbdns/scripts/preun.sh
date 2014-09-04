#!/bin/sh

if [ $1 = 0 ] ; then
    rm /service/dnscache
    rm /service/tinydns

    /usr/local/bin/svc -t /etc/service/dnscache /etc/service/dnscache/log
    /usr/local/bin/svc -t /etc/service/tinydns /etc/service/tinydns/log
fi
