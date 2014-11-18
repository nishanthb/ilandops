#! /usr/local/bin/perl -w
use strict;

#use Socket;
#use CGI;

select(STDERR); $|=1;
select(STDOUT); $|=1;

my $f = "/JumpStart/profiles/.";

if (-d $f) {
    print "Content-type: application/octet-stream\n\n";
    chdir $f;  
    my $cmd = "find . -type f -name '[A-Z]*' '!' -name '*.yaml'| pax -w";
    my $tar = `$cmd`;
    print $tar;
} else {
    print "Content-type: text/ascii\n\nboot server missing $f\n";

}


