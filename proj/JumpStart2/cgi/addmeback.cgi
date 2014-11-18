#! /usr/local/bin/perl
use Socket;
use CGI qw/:standard/;
use Seco::AwesomeRange qw(:common);
use strict;

my $QUEUE = "/JumpStart/var/addmeback.q";

close(STDERR); open(STDERR,">&STDOUT");
select(STDERR); $|=1;
select(STDOUT); $|=1;

print "Content-type: text/plain\n\n";

my $ip = $ENV{"REMOTE_ADDR"};
my $iaddr = inet_aton($ip);
my ($name,$aliases,$addrtype,$length,@addrs) = gethostbyaddr($iaddr,AF_INET);
unless ($name =~ /./) { 
    die "Check reverse dns";
    exit;
}

for ($name) {
    s#.inktomi.com$##;
    s#.inktomisearch.com$##;
    s#.yst.corp.yahoo.com$##;
}

print "INFO: name=$name\n";

my $cluster;
if ($cluster = param("cluster")) {
    die "Bad cluster name (syntax): $cluster" unless ($cluster =~ m/^([-a-zA-Z0-9_]+)$/);
    my ($test) = expand_range("\%${cluster}:ALL,&$name");
    if ($test) {
        print "INFO: Confirmed $name is in cluster ${cluster}:ALL\n";
    } else {
        die "You specified cluster $cluster, but node $name is not in ${cluster}:ALL";
    }
}

($cluster) = expand_range('*' . $name) unless (defined $cluster);

if ($cluster) {
    print "INFO: cluster=$cluster\n";
} else {
    die "No cluster found";
}

# check to see if the host is "down"
my ($test) = expand_range("\%${cluster}:{CLUSTER,ALL},&$name");
unless ($test) {
  print "WARNING: $name is not currently in \%${cluster}:{CLUSTER,ALL}\n";
  print "SUCCESS\n";
  exit 0;
}


system("mkdir","-p",$QUEUE) unless (-d $QUEUE);
die "Failed to create $QUEUE" unless (-d $QUEUE);

open(QUEUE,">$QUEUE/.$name") or die "Failed to create $QUEUE/.$name : $!";
print QUEUE "cluster: $cluster\n";
close QUEUE;

unlink("$QUEUE/$name");
rename("$QUEUE/.$name","$QUEUE/$name");

print "INFO: Queued $QUEUE/$name to rejoin cluster $cluster\n";
print "SUCCESS\n";
system("/JumpStart/cgi/addmebackd");
exit 0;


