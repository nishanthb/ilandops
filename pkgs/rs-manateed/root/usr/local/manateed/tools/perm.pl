#!/usr/local/bin/perl -w

#
# PERM - Production Engineering Release Manatement - Manateed Support Tool
#

use strict;
use Seco::AwesomeRange qw/:common/;


my $command = shift @ARGV;

if 		(! defined $command) { die "No command given\n"; }
if 		($command eq "check") { check(); }
elsif	($command eq "setup") { setup(); }
elsif	($command eq "start") { handle_init("start"); }
elsif	($command eq "stop") { handle_init("stop"); }
else 	{ die "Command $command unknown.\n"; }

sub setup {

	my $hostname = `hostname`;
	chomp $hostname;	

	my $cluster = shift @ARGV;
	my $admin = shift @ARGV;

	if (! $cluster ) {
		$cluster = `/home/seco/candy/bin/whoismycluster`;	
		chomp ($cluster);
	}
	if (! $admin ) {
		$admin = `/home/seco/candy/bin/whoismyadmin`;	
		chomp ($admin);
	}

	if (! $cluster ) {
		die "ERROR: Cluster name not given and cannot be determined\n";
	}

	if (! $admin ) {
		die "ERROR: Admin name not given and cannot be determined\n";
	}


	# ok, now we have enough info to run the setup script
	system ("/usr/local/bin/rexec ${admin}::perm/$cluster/.setup.pl");
}

sub check {
    my $releases = "/perm/";
    my %files;
    my $file;
    opendir(DIR, $releases) || die "Can't opendir $releases: $!" ;
    while ( defined ($file = readdir(DIR) )  ) {
        if (-l "$releases/$file" ) {
            $files{$file} = readlink("$releases/$file");
        }
    }
    closedir DIR;

    foreach my $i (keys %files) {
        print "$i:$files{$i}\n";
    }
}

sub handle_init {

	my ($action) = @_;

	my $modifier = shift @ARGV;
	$modifier ||= "";


my $hostname = `/bin/hostname`;
chomp $hostname;

my $cluster;
my $realcluster = expand_range("*${hostname}");

my $permcluster = expand_range("%${realcluster}:PERMCLUSTER") ;
  if ( $permcluster) {
    $cluster = $permcluster;
    }
   else {
    $cluster = $realcluster;
}


	if (! $cluster ) {
		die "ERROR: Cluster name cannot be determined\n";
	}

	
    # ok, now we have enough info to run the scripts
	if ($action eq "stop") {
		my $cmd = "/perm/$cluster/.stop";
		if (-x $cmd) {
			system ("$cmd $modifier");
		} 
		else { die "$cmd not found or executable: $!" ; }
	}
	elsif ($action eq "start") {
		my $cmd = "/perm/$cluster/.start";
		if (-x $cmd) {
			system ("$cmd $modifier");
		} 
		else { die "$cmd not found or executable: $!" ; }

	}
}

