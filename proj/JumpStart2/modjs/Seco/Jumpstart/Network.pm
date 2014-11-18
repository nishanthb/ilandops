package Seco::Jumpstart::Network;

use 5.006;
use strict;
use warnings 'all';
use Seco::Jumpstart::Utils qw(:all);

our $VERSION = '1.0.0';

## stuff
sub new {
    my ($class, $cfg) = @_;
    bless { cfg => $cfg }, $class;
}

sub setup {
    my $self = shift;
    #XXX:(yuting): mtu value should be match with his father(adminhost)
    $self->get_mtu_boothost;
    return $self->redhat_net_interfaces if os() eq 'redhat';
    return $self->debian_net_interfaces if os() eq 'debian';
    return undef;
}        

sub get_mtu_boothost {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    #XXX:(yuting): just return 1500;
    #XXX:(yuting): and eth0_mtu default value will be allowed.
    #XXX:(yuting): but that is not rigorous.
    return "1500";
    
    my $cmd = 'echo "GET /jumpstart/mtu.cgi" | nc boothost 9999';
    
    print "# $cmd\n";
    my $res  = `$cmd`;
    print $res;
    
    my $eth_mtu = $cfg->get('eth0_mtu');
    my $mtu = $eth_mtu;
    
    if ($res =~ m/MTU=(\d+)/i) {
        $mtu = $1;
        if ((defined $eth_mtu) && ($mtu != $eth_mtu)) { 
            displaybold("WARNING: Changing eth0_mtu from $eth_mtu" . 
                        " to $mtu - to match the boothost\n");
        }
        my $primary_iface = $cfg->get('primary_iface');
        system("ifconfig $primary_iface mtu $mtu");
        $cfg->set('eth0_mtu', $mtu);
    }
    return $mtu;
}

sub redhat_net_interfaces {
    my $self = shift;
    my $cfg = $self->{cfg};
    my $eth = $cfg->get('network_ifaces');

    #XXX:(yuting): do nothing just return.
    #XXX:(yuting): use template_dir file .
    print "do nothing just return.\n";
    return ;
    
    my $file_prefix = "/mnt/etc/sysconfig/network-scripts/ifcfg-";
    system("rm -f ${file_prefix}eth?");
    
    my $num_interfaces = scalar keys %{$eth};
    # generate ifcfg-eth0 or ifcfg-eth1 depending on the primary nic
    
    my ($primary_iface, $broadcast, $ip, $netmask, $network) =
      map { $cfg->get($_) }
        qw/primary_iface broadcast ip netmask network/;
    
    open my $fh, ">${file_prefix}$primary_iface" or
      die "${file_prefix}$primary_iface: $!";
    print $fh <<EOT;
DEVICE=$primary_iface
BOOTPROTO=static
BROADCAST=$broadcast
IPADDR=$ip
NETMASK=$netmask
NETWORK=$network
ONBOOT=yes
EOT
    close $fh;
    
    if (--$num_interfaces > 0) {
        my $secondary_iface = $primary_iface eq "eth0" ?
          "eth1" : "eth0";
        open $fh, ">${file_prefix}$secondary_iface" or
          die "${file_prefix}$secondary_iface $!";
        print $fh <<EOT;
DEVICE=$secondary_iface
BOOTPROTO=static
ONBOOT=no
EOT
        close $fh;
        
    }
}

sub debian_net_interfaces {
    my $self = shift;
    my $cfg = $self->{cfg};
    my $eth = $cfg->get('network_ifaces');
    my ($primary_iface, $broadcast, $ip, $netmask, $network, $gateway) =
      map { $cfg->get($_) }
        qw/primary_iface broadcast ip netmask network gateway/;
    
    # Generate /etc/network/interfaces for non-rh boxes
    #
    open my $int, ">/mnt/etc/network/interfaces"
      or die "network/interfaces: $!";
    my $mtuvar = $cfg->get($primary_iface . "_mtu");
    print $int <<EOT;
# /etc/network/interfaces -- configuration file for ifup(8), ifdown(8)

# The loopback interface
auto lo
iface lo inet loopback
EOT
    
    print $int <<EOT;
auto $primary_iface
iface $primary_iface inet static
address $ip
netmask $netmask
network $network
broadcast $broadcast
gateway $gateway
EOT
    
    if($primary_iface eq 'eth0') {
        print $int "    up /sbin/ifconfig /usr/local/sbin/fix_eth0\n"
          if $mtuvar == 4500;
    } else {
        print $int "    up /sbin/ifconfig $primary_iface mtu 4500\n"
          if $mtuvar == 4500;
    }
    print $int "\n";
    close $int;
    
    open my $modconf, ">>/mnt/etc/modules.conf";
    print $modconf <<EOT;
EOT
    close $modconf;
}

1;
