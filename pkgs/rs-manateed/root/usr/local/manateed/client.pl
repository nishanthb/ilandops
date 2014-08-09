#!/usr/local/bin/perl

###########################################################################
# $Id: //depot/root/main/usr/local/manateed/client.pl#5 $
###########################################################################
# manateed client
# connects to a given host, and executes the specified command
###########################################################################
$| = 1;

require 5.002;

use strict;
use Socket;
use Getopt::Std;              # for getopts()

my ($remote,$port, $iaddr, $paddr, $proto, $line, $cmd);
###########################################################################
# Get args
###########################################################################
use vars '$opt_h', '$opt_a', '$opt_s', '$opt_p';

if( !(getopts("ha:s:p:")) || $opt_h || $#ARGV != 0) {
	print "Usage: client.pl [-h] [-a alarm] [-s server] [-p port] <command>\n";
	exit;
}

if( $opt_a)
{
	alarm( $opt_a);
} else {
	alarm( 10);
}

$cmd = $ARGV[0];

### Machine to connect to
$remote  = $opt_s || 'localhost';

### Port to connect to
$port = $opt_p || 12345;

### Look up the service name, if the port is not numeric
if ($port =~ /\D/) { $port = getservbyname($remote, $port) }

die "No port" unless $port;

### Prepare to open the socket (perl magic)
$iaddr   = inet_aton($remote)   || die "no host: $remote";
$paddr   = sockaddr_in($port, $iaddr);
$proto   = getprotobyname('tcp');

### Open up a socket, and connect to the remote host
socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || die "socket: $!";
connect(SOCK, $paddr)|| die "connect: $remote $port $!";

### Auto flush the socket
select (SOCK);
$|=1;
select STDOUT;

### Send the remote host the command
print SOCK "$cmd\n";

while ($line = <SOCK>)
{
	print $line;
} 

close (SOCK)|| die "close: $!";
