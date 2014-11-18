#!/usr/local/bin/perl -w

use strict;
use Seco::OpsDB;
use YAML;
use CGI;

print CGI::header("text/plain");

#my $hostname = CGI::param('hostname');
#$hostname =~ s/$/.inktomisearch.com/ unless $hostname =~ /\./;

#Seco::OpsDB->connect;
#my $node = Seco::OpsDB::Node->retrieve(name => $hostname);
#my $out = $node->model_info;

#my %out = %$out;
#$out{hw_raid_manuf} = undef;
#print YAML::Dump(\%out);

print YAML::Dump({nothing => 'none'});
print "\n";

