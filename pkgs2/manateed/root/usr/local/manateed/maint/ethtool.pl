#!/usr/bin/perl -w
use warnings;
use strict;

# runs netstat -i to find out which NIC is used
# then runs ethtool for every ARGV command
# only "safe commands" are allowed:  -, -r, -a
#
# "$0 -r -a -" is translated to "ethtool -r DEVNAME", "ethtool -a", "ethtool DEVNAME".
#
# the ehttool data and netstat data is printed to stdout
#
#  address complaints to chernyak@yahoo-inc.com 
#

print SAFE_ethtool(@ARGV);


sub SAFE_ethtool
{
    my ($if_stat,$ifstat_raw)=get_net_if_stat();
    my ($if)=grep !/^lo$/, keys %$if_stat;

    my @rv;
    unless (scalar @_) { # re received no arguments
	push @rv, 'options: "-" for query, "-r" for renegotiate, or "-a" to query pause parameters ' . "\n";
    }
    for my $op (@_)
    {
        die "unsupported param $op" unless $op eq '-' || $op eq '-r' ||$op eq '-a';
        $op='' if $op eq '-';
        push @rv, run("/usr/sbin/ethtool $op $if");
    }
    push @rv, $ifstat_raw;
    return join("==========\n",@rv);
}

sub get_net_if_stat
{
    my $data=run("netstat -i");
    my @header;
    my %result;
    while ($data=~/\G([^\n]*)\n/gs)
    {
        my $line=$1;
        next if $line eq 'Kernel Interface table';
        next if $line =~ /no statistics available/;
        my @fields=split ' ',$line ;
        die "unexpected number of fields: $line" unless @fields;
        @header=@fields, next unless @header;
        die "number of fields in\n\t$line\nis not the same as in header" unless @header == @fields;
       $result{$fields[0]}={map {$header[$_]=>$fields[$_]} 0..@fields-1};
    }
    die "unexpected number of interfaces" unless keys %result ==2;
    die "no loopback interface" unless defined $result{lo};
    return (\%result,$data);
}

sub run
{
    my ($cmd)=@_;
    my $result=join('', `$cmd`);
    my $exit_code=$?>>8;
    my $errno=$!;
    die "$cmd failed: $errno" if $errno;
    die "$cmd exited with exit code $exit_code" if $exit_code;
    return $result;
}

