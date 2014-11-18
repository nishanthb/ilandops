#! /usr/local/bin/perl -w
use Socket;
use strict;
use CGI qw/:standard/;
use Seco::Jumpstart::JS_Utils qw/read_file/;
use Seco::Jumpstart::HostRecord;
use Seco::AwesomeRange qw/:all/;
use YAML;

my $name = param('hostname');

unless ($name) {
    my $ip = $ENV{"REMOTE_ADDR"};
    my $iaddr = inet_aton($ip);
    $name = (gethostbyaddr($iaddr,AF_INET))[0];
}

print header("text/plain");

unless ($name =~ /./) { 
    generic_error("REVERSE DNS","Check reverse dns, I do not recognize $ENV{REMOTE_ADDR}");
}

for ($name) {
    s/.inktomisearch.com$//;
    s/.yst.corp.yahoo.com$//;
    s/.inktomi.com$//;
}

my $hr = Seco::Jumpstart::HostRecord->get($name);
my $group = $hr->label();
my $cfg = YAML::LoadFile("/JumpStart/profiles/$group.yaml");
my $installer_script = $cfg->{installer_script};
my $file = read_file("/JumpStart/cgi/$installer_script");
unless ($file) {
    generic_error("JS SERVER ERROR","Missing /JumpStart/cgi/$installer_script");
}
print $file;

sub generic_error {
    my ($banner,$msg) = @_;
    my $buffer = read_file("/JumpStart/cgi/installer-v0.txt");
    $buffer =~ s/GENERIC BANNER/$banner/g;
    $buffer =~ s/GENERIC DETAIL/installer.cgi: $msg/g;
    print $buffer;
    exit 0;
}
