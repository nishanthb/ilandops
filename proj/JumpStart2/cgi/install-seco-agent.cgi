#!/usr/local/bin/perl

use strict;
use warnings 'all';
use CGI qw/:standard/;

print header("text/plain");

print <<'EOT'

set -x

update-seco-agent
yum -e0 -d0 -y install yum
seco-agent -q --run=resolv.conf --once
IP=`perl -lane 'print $F[0] if /boothost/' /etc/hosts`
perl -lpi.sa -e "\$_=q() if /127.\\d/; if (not \$done and $. > 1) { print q(nameserver $IP); \$done=1 }" /etc/resolv.conf
seco-agent --run=yum.conf --once 
if [ ! -e /etc/yum.conf ] ; then
    echo YUM.CONF FAILED!
    echo "-----"
    cat /etc/resolv.conf
    echo "-----"
    sleep 5
    exit 1
fi
seco-agent --run=dpkg-list --once -q
seco-agent --once -q
EOT
