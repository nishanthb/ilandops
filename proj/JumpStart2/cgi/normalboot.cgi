#! /usr/local/bin/perl -w
use strict;
use CGI qw/:standard/;
use Socket;
use Seco::Jumpstart::NextBoot;
use Seco::Jumpstart::FirstBoot;

print header("text/plain");

my $name = param('hostname');
unless ($name) {
    my $ip = $ENV{"REMOTE_ADDR"};
    my $iaddr = inet_aton($ip);
    $name = (gethostbyaddr($iaddr,AF_INET))[0];
}

unless (length($name)) {
    print "Check reverse DNS\n";
    exit;
}
$name =~ s#.inktomi.com$##;
$name =~ s#.inktomisearch.com$##;
$name =~ s#.yst.corp.yahoo.com$##;

die "INVALID HOSTNAME\n" unless $name =~ /^[-\w.]+$/;

my ($boot, $timestamp, $user) = Seco::Jumpstart::NextBoot->get($name);
my $binboot = "/JumpStart/bin/boot --mode=normal -r '$name'";
if ($user) {
    $binboot .=  " -u $user";
}
$binboot .= " </dev/null";
Seco::Jumpstart::FirstBoot->set($name, "jumped", $user);
my $msg =`$binboot`;
print $msg; # for mod_perl

