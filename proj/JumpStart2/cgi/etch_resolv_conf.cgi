#! /usr/local/bin/perl

use strict;
use warnings 'all';
use CGI;

use Seco::Jumpstart::NextBoot;
use Seco::Jumpstart::FirstBoot;
use Seco::AwesomeRange qw/:all/;

my $q = CGI->new;
print $q->header("text/plain");
my $name = $q->param('hostname');

unless ($name) {
    print "NO\nNeed a hostname\n";
    return 0;
}

if($name =~ /\.jp2\./) {
	print <<EOF;
search ysm.jp2.yahoo.com jp2.yahoo.com yahoo.com
nameserver 124.108.64.200
nameserver 124.108.64.201
EOF
	exit(0);
}

if($name =~ /yss\.ird\./) {
	print <<EOF;
search ysm.ird.yahoo.com ird.yahoo.com yahoo.com
nameserver 87.248.99.160
EOF
	exit(0);
}

if($name =~ /\.ird\./) {
	print <<EOF;
search ysm.ird.yahoo.com ird.yahoo.com yahoo.com
nameserver 87.248.102.17
nameserver 87.248.102.18
nameserver 87.248.102.19
EOF
	exit(0);
}

if($name =~ /\.sk1\./) {
	print <<EOF;
search ysm.sk1.yahoo.com sk1.yahoo.com yahoo.com ysm.vip.sk1.yahoo.com
nameserver 72.30.124.13
nameserver 72.30.124.14

EOF
	exit(0);
}
if($name =~ /\.ac2\./) {
	print <<EOF;
search ysm.ac2.yahoo.com ac2.yahoo.com yahoo.com ysm.vip.ac2.yahoo.com
nameserver 74.6.244.10

EOF
	exit(0);
}
if($name =~ /\.kr2\./) {
	print <<EOF;
search ysm.kr2.yahoo.com kr2.yahoo.com yahoo.com
nameserver 123.0.0.136
nameserver 123.0.0.137
EOF
	exit(0);
}
if($name =~ /\.ac4\./) {
	print <<EOF;
search ysm.ac4.yahoo.com ac4.yahoo.com yahoo.com
nameserver 76.13.6.26
nameserver 76.13.6.24
EOF
	exit(0);
}
if($name =~ /\.cc1\./) {
	print <<EOF;
search ysm.cc1.yahoo.com cc1.yahoo.com yahoo.com
nameserver 74.6.179.136
nameserver 74.6.179.137
EOF
	exit(0);
}

