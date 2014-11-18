#! /usr/local/bin/perl -w
use Socket;
use CGI qw/:standard/;
use Seco::Jumpstart::NextBoot;
use Seco::Jumpstart::HostRecord;

select(STDERR); $|=1;
select(STDOUT); $|=1;

$ip = $ENV{"REMOTE_ADDR"};
$iaddr = inet_aton($ip);
$name = (gethostbyaddr($iaddr,AF_INET))[0];

unless ($name =~ /./) { 
    print "Check reverse DNS\n";
    exit;
}

print header("text/plain");

for ($name) {
    s/.inktomisearch.com$//;
    s/.yst.corp.yahoo.com$//;
    s/.inktomi.com$//;
#    s/(\..*)\.yahoo.com$//;
}

my $hr = Seco::Jumpstart::HostRecord->get($name);

unless ($hr->admin) {
    print "EMPTY HOST RECORD!\n";
    exit;
}

$hr->dump_hostrecord(Seco::Jumpstart::NextBoot->get($name));

