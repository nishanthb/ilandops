#!/usr/local/bin/perl -w

## NOTICE
## Is this script failing due to /secoperl missing?  
## http://twiki.corp.yahoo.com/view/YSTProdEng/SecoPerl

###########################################################################
# $Id: //depot/manatee/main/tools/bin/allmanateed.pl#37 $
###########################################################################
# Connect to all the manateeds in the given cluster, and run the specified
# command
###########################################################################

use Getopt::Long;
use Symbol;		### For creating multiple file handle references
use strict;		### Avoid typos
use FindBin '$Bin';	### Ensure we can find libraries
use Data::Dumper;

use Seco::AwesomeRange qw(:common);
#require "anyrange.pl";

Getopt::Long::Configure(qw(no_ignore_case));



BEGIN { unshift(@INC,"$Bin/../lib","/home/seco/tools/lib") }

use vars '$Err', '%argv';

my( $cluster, $type, $cmd);
my( %nodes, @nodes, $host, $port, $timeout);

###########################################################################
# Get arguments
###########################################################################

if( !(GetOptions(\%argv,"h|help","a|alarm=s","r|range=s","c|cluster=s","x|exclude=s",
"perl=s",
"t|timeout=s","p|port=s","m|maxflight=s","s|sleep=s","randomize","tcp-timeout=s","f|fast","F|faster","collapse",
                 "v|verbose")) || $argv{"h"} || $#ARGV < 0)
{
	print STDERR "Usage: $0 [-h] [-a <alarm>] [-t <timeout>] [-p <port>] [-r] [-c] <nodes> <cmd>\n";
	print STDERR "\tExecute a command via the manateed daemon on every node in a cluster.\n";
	print STDERR "\t<cluster> can be of the form CLUSTER or CLUSTER:TYPE.  See\n";
	print STDERR "\tthe cluster's nodes.cf file for more details.\n";
	print STDERR "\t-h Display this information.\n";
	print STDERR "\t-a terminate the program after given number of seconds\n";
	print STDERR "\t-c specify nodes via a cluster\n";
	print STDERR "\t-r specify a range of nodes\n";
	print STDERR "\t-x specify a range to exclude\n";
	print STDERR "\t-t timeout for waiting to read data from a node (default 30)\n";
	print STDERR "\t-p port manateed is running on each node (default 43698)\n";
	print STDERR "\t-m max in-flight TCP sessions to have at once (default: 0)\n";
	print STDERR "\t-s sleep time to sleep between hosts (default: 0)\n";
	print STDERR "\t-v verbosity when opening/closing connections\n";
        print STDERR "\t--randomize the connection order\n";
        print STDERR "\t--tcp-timeout 5   (tcp connection timeout)\n";
        print STDERR "\t--fast   (faster ManateedClient backend)\n";
        print STDERR "\t--faster   (faster-er Seco::MultipleTcp backend)\n";
        print STDERR "\t--collapse show only ranges and unique answers (implies -F)\n";
	exit(0) if( $argv{"h"});
	exit(1);
}

## old perl on solaris, just ignore -f
#if ($argv{f} and $^O eq "solaris") {
#	delete $argv{f};
#	warn "don't use -f on solaris, please";
#}
#if ($argv{F} and $^O eq "solaris") {
#	delete $argv{f};
#	warn "don't use -F on solaris, please";
#}


my $fallback=0;
my $alarm = (defined  $argv{"a"}) ? $argv{"a"} : 180;  
my %collapse;

#$argv{"F"}=1 if ($argv{"collapse"});  # Force Seco::MultipleTcp for now
$argv{"F"}=1 ;

if ($argv{F}) {
        eval "use Seco::MultipleTcp;";
        if ($@) {
          print STDERR "falling back to AllManateed\n";
          delete $argv{"F"};
          eval "use Seco::AllManateed";
        }
} elsif ($argv{f}) {
	die "new interface doesn't support -s"
		if ($argv{"s"});
	eval "use ManateedClient;";
        if ($@) {
          print STDERR "falling back to AllManateed\n";
          delete $argv{"f"};
          eval "use Seco::AllManateed";
        }
} else {
	eval "use Seco::AllManateed";
}

$argv{"c"} = shift @ARGV if ((!$argv{"r"}) && (!$argv{"c"}));

my $range = "";
if ($argv{"c"}) {
  $range .= " ,%{$argv{c}} ";
}
if ($argv{"r"}) {
  $range .= " ,{$argv{r}}";
}
if ($argv{"x"}) {
  $range .= " ,-{$argv{x}}";
}

@nodes = expand_range($range);


if ($argv{"F"}) {
  do_faster();
} elsif ($argv{"f"}) {
  do_fast();
} else {
  do_slow();
}

if (keys %collapse) {
  foreach my $key (sort keys %collapse) {
     my $k = $key; chomp $k;
     my $range = compress_range(keys %{$collapse{$key}});
     print "$range $k\n";
  }
}

sub do_slow {
  ### Be able to break out of blocking calls
  alarm ($alarm);

  ### Actually do the commands
  foreach $cmd (@ARGV)
  {
          my($am) = new Seco::AllManateed;
          $am->port($argv{"p"} || 43698);
          $am->sleep($argv{"s"} || 0);
          $am->tcp_timeout($argv{"tcp-timeout"} || 5);
          $am->read_timeout($argv{"t"} || 30);
          $am->maxflight($argv{"m"});
          #$am->debug($argv{"v"});
          $am->randomize($argv{"randomize"}||0);
          my(%results) = $am->command(join(",",@nodes), $cmd);
          my($key,$line,@results);

          ### Print any connection errors
          foreach $key (sort keys(%{$am->{errors}}))
          {
            print STDERR "WARNING: $key: ", join(";",@{$am->{errors}{$key}}),"\n";
          }

          ### Print results
          foreach $key (sort keys %results) {
            @results = @{$results{$key}};
            pop @results if (($#results>=0) && ($results[$#results] =~ /^$/));
            foreach $line (@results) {
              print "$key: $line\n";
            }
          }
  }

}



sub do_fast {
  ### Be able to break out of blocking calls
  alarm ($alarm);

  ### Actually do the commands
  foreach $cmd (@ARGV)
  {
          my($am) = new ManateedClient;
          $am->port($argv{"p"} || 43698);
          $am->timeout($argv{"tcp-timeout"} || 5);
          $am->maxflight($argv{"m"} || 100);
          $am->debug($argv{"v"});
          $am->nodes(@nodes);
          $am->randomize($argv{"randomize"}||0);
          $am->command($cmd);

          my $res = $am->run();
          foreach my $node (@nodes) {
                 if (! exists ${$res}{$node}) {
                    print STDERR "WARNING: ${node}: unknown error\n";
                    next;
                 }
                 my %nobj = %{${$res}{$node}};
                 my $s; 
                 if ($s = $nobj{error}) {
                    print STDERR "WARNING: ${node}: $s\n";
                    next;
                 }
                 if ($s = $nobj{write_err}) {
                    print STDERR "WARNING: ${node}: $s\n";
                    next;
                 }
                 if ($s = $nobj{read_err}) {
                    print STDERR "WARNING: ${node}: $s\n";
                    next;
                 }
                 if (($s = $nobj{sock_err}) || (! $nobj{written})) {
                    print STDERR "WARNING: ${node}: socket or write error\n";
                    next;
                 }
                 $s = $nobj{output};
                 if ((defined $s) && (length($s))) {
                    chomp $s;
                    print "${node}: $_\n" foreach (split(/\n/,$s));
                 }
          
          }
  }
}


sub doperl {
    $_ = shift @_;
    eval $argv{"perl"} if ( $argv{"perl"} );
    return $_;
}


sub do_faster {
    ### Be able to break out of blocking calls
    alarm($alarm);

    ### Actually do the commands
    foreach $cmd (@ARGV) {
        my ($am) = new Seco::MultipleTcp;
        $am->port( $argv{"p"}                   || 43698 );
        $am->minimum_time( $argv{"s"}           || 0 );
        $am->sock_timeout( $argv{"tcp-timeout"} || 60 );
        $am->maxflight( $argv{"m"}              || 100 );

        #$am->debug($argv{"v"});
        $am->nodes(@nodes);
        $am->shuffle( $argv{"randomize"} || 0 );
        $am->writebuf( $cmd . "\n" );

        if ( $argv{"v"} ) {
            $am->yield_sock_start(
                sub {
                    my ( $self, $node ) = @_;
                    my $port = $self->port();
                    print STDERR "making sock for host: ${node} port $port \n";
                }
            );
        } ## end if ( $argv{"v"} )

        my $res = $am->run();
        if ( $argv{"collapse"} ) {
            foreach my $node (@nodes) {
                my $obj = ${$res}{$node};
                my $s;
                if ( $s = $obj->error() ) {
                    $s=doperl($s);
                    $collapse{"WARNING: $s"}{$node}=1;
                    next;
                }
                if ( $s = $obj->write_error() ) {
                    $s=doperl($s);
                    $collapse{"WARNING: $s"}{$node}=1;
                    next;
                }
                if ( $s = $obj->read_error() ) {
                    $s=doperl($s);
                    $collapse{"WARNING: $s"}{$node}=1;
                    next;
                }
                $s = $obj->readbuf();
                    $s=doperl($s);
                if ( length($s) ) {
                    $collapse{"$s"}{$node}=1;
                } else {
                    $collapse{"no response"}{$node}=1;
                }
            } ## end foreach my $node (@nodes)
        } else {
            foreach my $node (@nodes) {
                my $obj = ${$res}{$node};
                my $s;
                if ( $s = $obj->error() ) {
                    print STDERR "WARNING: ${node}: $s\n";
                    next;
                }
                if ( $s = $obj->write_error() ) {
                    print STDERR "WARNING: ${node}: $s\n";
                    next;
                }
                if ( $s = $obj->read_error() ) {
                    print STDERR "WARNING: ${node}: $s\n";
                    next;
                }
                $s = $obj->readbuf();
                if ( length($s) ) {
                    chomp $s;
                    print "${node}: $_\n" foreach ( split( /\n/, $s ) );
                }

            } ## end foreach my $node (@nodes)
        } ## end else [ if ( $argv{"collapse"})

    } ## end foreach $cmd (@ARGV)

} ## end sub do_faster

