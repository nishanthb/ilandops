#!/usr/local/bin/perl
use strict;
use warnings 'all';
use Socket;
use Seco::AwesomeRange qw/:common/;
use CGI qw/:standard/;

my $hostname = param("hostname");
unless ($hostname) {
    my $ip = $ENV{"REMOTE_ADDR"};
    my $iaddr = inet_aton($ip);
    my $name = (gethostbyaddr($iaddr,AF_INET))[0];
    unless ($name =~ /./) { 
        print "Content-type: text/ascii\n\nCheck reverse DNS\n";
        exit;
    }
    $hostname = $name;
}

for ($hostname) {
    s/\.inktomi(search)?\.com$//;
    s/[^a-z0-9A-Z.\-]//g;  # Remove any dangerous characters
}

print header("text/plain");
print "checking $hostname\n";

my @cluster = expand_range("*$hostname");
if (@cluster != 1) {
    print "ERROR: We don't recognize the cluster name for node $hostname\n";
    exit;
}

my $cluster = $cluster[0];
my @nodes = expand_range("%$cluster");
my %nodes; @nodes{@nodes} = undef;
if (exists $nodes{$hostname}) {
    print "SUCCESS: $hostname is in cluster $cluster\n";
} else {
    print "ERROR: $hostname is not in cluster $cluster\n";
}

