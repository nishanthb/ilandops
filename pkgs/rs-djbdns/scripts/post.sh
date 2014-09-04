#!/bin/bash

PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin
export PATH

test -d /etc/service/dnscache/ && svc -dxt /etc/service/dnscache
test -d /etc/service/tinydns/ && svc -dxt /etc/service/tinydns
rm -rf /etc/service/tinydns/{root,root-stage}
ln -sfn /export/crawlspace/dns-data/tinydns/root /etc/service/tinydns/root
ln -sfn /export/crawlspace/dns-data/tinydns/root-stage /etc/service/tinydns/root-stage
mkdir -p /export/crawlspace/dns-data/{dn,tinydns/root,tinydns/root-stage}

# dnscache
mkdir -p /etc/service/dnscache/log/main
chown 65399 /etc/service/dnscache/log/main
ln -sfn /etc/service/dnscache /service/dnscache

# tinydns
IP=`/etc/service/tinydns/find-primary-eth-ip`
echo Setting IP to $IP
echo $IP > /etc/service/tinydns/env/IP
mkdir -p /etc/service/tinydns/log/main
chown 65399 /etc/service/tinydns/log/main
ln -sfn /etc/service/tinydns /service/tinydns

/usr/local/bin/svc -t /service/tinydns /service/tinydns/log
/usr/local/bin/svc -t /service/dnscache /service/dnscache/log
