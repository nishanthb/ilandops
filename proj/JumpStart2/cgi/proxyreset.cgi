#! /usr/local/bin/perl -w

# Usage:
#  http://hostname/jumpstart/proxyreset.cgi
#      indicate to the server that you just bounced
#      (updates /JumpStart/var/proxyresets/*)
#  http://hostname/jumpstart/proxyreset.cgi?foo
#      gets a list of hostnames and times


use strict;
use Socket;

select(STDERR); $|=1;
select(STDOUT); $|=1;

my $query = $ENV{"QUERY_STRING"};
my $ip = $ENV{"REMOTE_ADDR"};
my $iaddr = inet_aton($ip);
my $name = (gethostbyaddr($iaddr,AF_INET))[0];
my $statedir = "/JumpStart/var/proxyresets";

unless (-d $statedir) {  
  system("mkdir -p $statedir");
}

print "Content-type: text/ascii\n\n";

unless (length($name)) { 
    print "Check reverse DNS\n";
    exit;
}
$name =~ s#.inktomi.com$##;
$name =~ s#.inktomisearch.com$##;
$name =~ s/[^a-z0-9\._-]/_/g;   # Bogus chars


if ($query =~ /./) { 
   chdir $statedir || die "Failed to chdir $statedir\n";
   opendir(DIR,".");
   while(my $file = readdir DIR) {
     next unless (-f $file);
     my $mtime = (stat($file))[9];
     print "$file $mtime\n";
   }
} else {
   unlink("$statedir/$name");
   open(TOUCH,">$statedir/$name");
   close TOUCH;
}
