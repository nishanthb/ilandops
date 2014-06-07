package Seco::Jumpstart::EthersCfg;

use strict;
use warnings 'all';

use constant ETHERS_CF => "/usr/local/jumpstart/conf/ethers.cf";

use Seco::Jumpstart::HostRecord;
use Seco::Jumpstart::JS_Utils qw/fqdn/;
use Seco::Jumpstart::DB;

use base 'Seco::Jumpstart::BaseCfg';
use fields qw/macs opsdb_macs/;

use Seco::OpsDB;
Seco::OpsDB->connect;

{
    my $instance;

    sub instance {
        return $instance if $instance;

        $instance = __PACKAGE__->new;
    }
}

sub new {
    my ($class, $filename) = @_;

    $filename ||= ETHERS_CF;
    my $self = fields::new($class);
    $self->SUPER::new;
    $self->_parse_ethers($filename);
    $self->_get_opsdb_macs();
    return $self;
}

sub _parse_ethers {
    my ($self, $filename) = @_;

    my %result;
    my %seen_host;
    my %seen_mac;
    open my $fh, "<$filename" or die "$filename: $!";
    while (<$fh>) {
        s/#.*$//gm;
        s/^\s+//;
        s/\s+$//;
        next unless $_;
        my ($ether, $node) = split;
        $self->log('info', "Duplicate mac address: $node $seen_mac{$ether}")
          if $seen_mac{$ether};
        $self->log('info', "Duplicate ethers.cf entry for $node")
          if $seen_host{$node};
        $seen_host{$node}++;
        $seen_mac{$ether} .= " $node";

        $result{$node} = $ether;
    }
    close $fh;

    $self->{macs} = \%result;
}

sub _get_opsdb_macs {
    my $self = shift;
    my $macs = Seco::OpsDB::Node->getallmacs();
    $self->{opsdb_macs} = $macs;
}

sub mac {
    my ($self, $node) = @_;

    my $mac_table = $self->{macs};
    my $mac       = $mac_table->{$node};
    return $mac if $mac;

    my $fq_node = fqdn($node);
    return $self->{opsdb_macs}{$fq_node};
}

1;
