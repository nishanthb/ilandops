#!/usr/local/bin/perl 
use warnings;
use strict;
use CGI qw/:standard/;
use Socket;
use Seco::Jumpstart::Overrides;

print header("text/plain");

unless (param()) {
    print "INFO: No overrides specified. Ignoring\n";
    exit;
}

my $name = param('hostname');
unless ($name) {
    my $ip = $ENV{"REMOTE_ADDR"};
    my $iaddr = inet_aton($ip);
    $name = (gethostbyaddr($iaddr,AF_INET))[0];
}

for ($name) {
    s/\.inktomisearch\.com$//;
}

# Update the overrides DB 
for my $param (param()) {
    next if $param eq "hostname";
    my $value = param($param);
    my $override = Seco::Jumpstart::Overrides->update($name, $param, $value);
}
#Seco::Jumpstart::Overrides->commit;

print "INFO: Overrides updated for $name\n";
