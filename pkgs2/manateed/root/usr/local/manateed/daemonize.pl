#!/usr/local/bin/perl -w

###########################################################################
# $Id: //depot/root/main/usr/local/manateed/daemonize.pl#1 $
###########################################################################
# Runs an arbitrary command in daemon mode.  this means close all 
# file handles, cd to /, and set the umask correctly
###########################################################################

use Getopt::Std;		# for getopts()

use vars '$opt_n', '$opt_h';

my( $cmd, @args);

###########################################################################
# Get args
###########################################################################
if( !(getopts("n:h")) || $opt_h || $#ARGV < 0) {
        print "Usage: daemonize.pl [-nodaemon]\n";
	print "\t-nodaemon is useful for debugging\n";
        exit;
}

### Get the command to daemonize
$cmd = shift( @ARGV);
@args = @ARGV;

### the -n option will cause us to not run in daemon mode
### to help track down bugs with executing the child process 
### (like command not found :>)                          
if( $opt_n)
{
	print "Running in nodeamon mode for testing\n";
	print "$cmd @args\n";
} else {
	### Need to fork off a new process	
	if (!defined($pid = fork)) {
		print STDERR "ERROR: could not fork '$!'\n";
        } elsif ($pid) {
		exit;  ### exit out of parent process
        }
	chdir( "/");
	umask(0);

	close( STDIN);
	close( STDOUT);
	close( STDERR);
}

exec( $cmd, @args);

