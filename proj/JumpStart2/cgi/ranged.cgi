#!/usr/local/bin/perl

use strict;
use CGI ':cgi';
use Libcrange;
use Seco::Data::Range;

my $oper = path_info();
my $range = param('keywords');

print header('text/plain');
my @param = param();

if ($oper eq '/list' or $oper eq '/expand') {
    my @result = Libcrange::expand($range);
    if ($oper eq '/list') {
        print "$_\n" for @result;
    } 
    else {
        my $r = Seco::Data::Range->new;
        print $r->compress(\@result), "\n";
    }
}
