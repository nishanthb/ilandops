#! /usr/local/bin/perl -w
use strict;
use File::Slurp;
use CGI;
use Socket;

my $q = CGI->new;
my $name = get_remote_hostname($q);
my $name_with_no_dots = $name;
$name_with_no_dots =~ s/\..*$//;

my $dir = substr($name_with_no_dots, -2);
my $f = "/JumpStart/ssh-keys/$dir/$name.tar";

if (-f $f) {
    print $q->header(-type => "application/octet-stream");
    my $file = read_file($f);
    print $file;
} else {
    print $q->header(-type => "text/ascii");
    print "\nNo keys for $name\n";
}

sub get_remote_hostname {
    my $q = shift;
    my $name = $q->remote_host;
    if ($name =~ /^\d/) {
        my $iaddr = inet_aton($name);
        $name = (gethostbyaddr($iaddr, AF_INET))[0];
    }

    unless ($name =~ /./) { 
        print $q->header(-type=>"text/ascii");
        print "\nCheck reverse DNS\n";
        exit;
    }
    $name =~ s#.inktomi.com$##;
    $name =~ s#.inktomisearch.com$##;
    $name =~ s#.yst.corp.yahoo.com$##;
    return $name;
}
