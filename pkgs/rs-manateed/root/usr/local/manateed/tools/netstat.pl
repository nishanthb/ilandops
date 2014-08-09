#!/home/tops/bin/perl  -w 
#
use strict;
use Getopt::Long;
use Pod::Usage;

my $port;
my $help;
GetOptions('port=i' => \$port, 'help' => \$help) or pod2usage(2);
pod2usage(-verbose => 2) if $help;
pod2usage(2) if @ARGV;

$ENV{PATH}="/sbin:/usr/sbin:/bin:/usr/bin";

open NETSTAT, "netstat -n -t|" or die "netstat: $!";
while (<NETSTAT>) {
    next unless (/ESTABLISHED/);
    next if $. <= 2;
    my ($local, $remote) = (split)[3..4];
    if ($port) { 
      next unless (($local =~ m/:$port$/) || ($remote =~ m/:$port$/));
    }
    print "$local $remote\n";
}
close NETSTAT or die "$!";


__END__

=head1 NAME

netstat.pl - Prints statistics about tcp connections

=head1 SYNOPSIS

netstat.pl [options]

 Options:
    --help          full documentation
    --port=<port>   restrict statistics to this port only

=head1 DESCRIPTION

TODO: write description :)

=cut


