#! /usr/local/bin/perl

use strict;
use warnings 'all';
use CGI qw/:standard/;
use Seco::AwesomeRange qw/:common/;
use Sys::Hostname;
use Socket;

Seco::AwesomeRange::want_warnings(0);

print header("text/plain");
my $hostname = param('hostname');
unless ($hostname) {
    print "ERROR: no hostname parameter\n";
    exit 0;
}

my $host_ip = inet_ntoa(scalar gethostbyname($hostname));
unless ($host_ip) {
    print "ERROR: can't resolve $hostname\n";
    exit 0;
}

my $myhost = hostname();

if ($myhost =~ /^hkadmin/) {
    print "124.108.93.70\n";
    exit;
}

if ($myhost =~ /^pikachu/) {
    print "202.93.94.203\n";
    exit;
}

if($hostname =~ /\.ysm\.ird/) {
    print "87.248.99.161\n";
    exit;
}

if ($hostname =~ /^ad\d\d\d\d\.yss.ac2/) {
    print "74.6.244.10\n";
    exit;
}

#if($hostname =~ /^af\d\d\d\d\.yss\.sk1/) {
#   print "74.6.155.22\n";
#}

#if($hostname =~ /^af\d\d\d\d\.yss\.ac2/) {
#   print "72.30.191.168\n";
#}

if($hostname =~ /^rc6\d\d\d\.yss\.ac2/) {
   print "72.30.191.168\n";
}

#if($hostname =~ /^af\d\d\d\d\.yss\.kr2/) {
#   print "123.0.0.180\n";
#}

if($hostname =~ /^af\d\d\d\d\.yss\.ird/) {
   print "87.248.99.160\n";
   exit;
}

my @cool_boothosts = expand_range('@BOOTHOST & (@AC2,@AC4,@SK1,@CC1)');
my %cool; @cool{@cool_boothosts} = undef;

my $sv;
if (exists $cool{$myhost}) { 
    $sv = $myhost;
} elsif ($myhost eq "worry") {
    print "74.6.252.10\n";
    exit;
} else {
    my $COLO = "hosts_dc(dc($hostname))";
    my $hint_colo = get_hints_colo();
    $COLO = $hint_colo if $hint_colo;
    my @repos = expand_range("$COLO & \@YUMREPO");
    my $last_octect = $host_ip;
    $last_octect =~ s/.*\.//;
    $sv = $repos[$last_octect % @repos];
}

unless ($sv) {
    print "ERROR: No yumrepo found\n";
    exit;
}

my $ip = inet_ntoa(scalar gethostbyname($sv));
print "$ip\n";

sub get_hints_colo {
    my $ret;
    open my $hints_fh, "<" , "/etc/gemstonehints" or return;
    while (<$hints_fh>) {
           chomp;
           if (/^COLO=(.*?)$/) {
              $ret ='@' . $1;
           }
        }
    close $hints_fh;
    return $ret;
}
