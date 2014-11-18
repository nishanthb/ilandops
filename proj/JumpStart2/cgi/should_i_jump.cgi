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

for ($name) {
    s/.inktomisearch.com$//;
    s/.yst.corp.yahoo.com$//;
    s/.inktomi.com$//;
}

if ($name =~ /^(nyn|nynflow)\d/) {
    print "YES\nnyn nodes are always allowed.\n";
    return 0;
}

# First Rule. OK if recent bin/boot
my ($boot, $timestamp, $user) = Seco::Jumpstart::NextBoot->get($name);
$timestamp = 0 unless defined $timestamp;
if ((time() - $timestamp) < 4 * 3600) {
    print "YES\n";
    my $date = localtime($timestamp);
    $date =~ s/ /-/g;
    print "recent timestamp: $date by $user\n";
    exit;
}

# Second Rule. OK if --firstjump
($boot, $timestamp, $user) = Seco::Jumpstart::FirstBoot->get($name);
if (defined $boot and $boot eq "first") {
    print "YES\n";
    my $date = localtime($timestamp);
    $date =~ s/ /-/g;
    print "firstjump: $date by $user\n";
    exit;
}

my $info_msg = "Re-run the bin/boot command if you really want to jump this node.\n";
my @cluster = expand_range("*$name");
if (@cluster != 1) {
    # we need one cluster, so there must be something
    # wrong here. Just assume it's not ok to jump
    my @ech = expand_range('%ech:PULLED');
    my %ech; @ech{@ech} = undef;
    if (exists $ech{$name}) {
	print "YES\n";
	print "Node has been pulled from echelon\n";
    } else {
	print "NO\n";
	system("/JumpStart/bin/boot -r $name -m n -u $user");
	print "Can't determine cluster\n$info_msg";
    }
    exit;
}

my @nodes = expand_range("%$cluster[0]");
my %nodes; @nodes{@nodes} = undef;
if (exists $nodes{$name}) {
    print "NO\nNode in service ($cluster[0])\n$info_msg";
    system("/JumpStart/bin/boot -r $name -m n -u $user");
} else {
    print "YES\nNode not in the rotation ($cluster[0])\n";
}
