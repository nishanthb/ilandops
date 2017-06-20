#!/usr/local/bin/perl -w -T
#

use strict;
use Getopt::Long;
use Pod::Usage;

$ENV{PATH} = "/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin";

my $vtysh;
my @vtyshs= qw( /export/crawlspace/quagga/bin/vtysh /usr/bin/vtysh );
my @services = qw( /service/ospfd /service/zebra );


my $help = 0;
GetOptions('help' => \$help) or pod2usage(2);
pod2usage(-verbose => 2) if $help;
pod2usage(2) if @ARGV < 2 or @ARGV > 3;

# Get and validate arguments
my $t_vip = shift;
defined $t_vip and $t_vip =~ /^(\d+\.\d+\.\d+\.\d+)$/ or die pod2usage(2);
my $vip = $1;

my $t_cmd = shift;
defined $t_cmd and $t_cmd =~ /^(up|down)$/ or die pod2usage(2);
my $cmd = $1;

if ($cmd eq 'up') {
    my $t_iface = shift;
    pod2usage(2) if @ARGV;

    defined $t_iface and $t_iface =~ /^([\w:]+)$/ or die pod2usage(2);
    my $iface = $1;

    vip_up($vip, $iface);
} else {
    my $t_iface = shift if (@ARGV); # ignore the interface
    pod2usage(2) if @ARGV;
    vip_down($vip);
}

# returns true if the interface passed as an arg. is UP
# ls_dev = output of ip addr dev $device
sub interfaceUp {
    my ($ls_dev, $wanted) = @_; 
    return 0 unless $ls_dev =~ /\bUP\b/;
    return $ls_dev =~ /\b$wanted\b/;
}

sub getNetmask {
    my $ls_dev = shift;
    if ( $ls_dev =~ m{\d+\.\d+\.\d+\.\d+/(\d+)}) {
        return $1;
    } else {
        die "ERROR: Couldn't determine netmask: $ls_dev\n";
    }
}

sub vip_up {
    my ($vip, $label) = @_;
    return vip_up_loopback(@_) if ($label =~ m/^lo/);

    my $dev = $label;
    $dev =~ s/:\d+$//;
    my $ls_dev = `ip addr ls dev $dev 2>&1`;
    chomp $ls_dev;
    die "ERROR: $ls_dev\n" if $?;

    # Verify that the interface is not up
    interfaceUp($ls_dev, $label) and
        die "ERROR: interface '$label' is already up.\n";

    # Duplicate address detection: send 1 probe and wait for 1 sec
    system("arping","-q","-c","1","-w","1","-D","-I","$dev","$vip");
    die "ERROR: Some host already uses $vip\n" if $?;

    my $netmask = getNetmask($ls_dev);
    print "INFO: bringing up $vip on $dev label $label\n";
    if (system("ip", "addr", "add", "$vip/$netmask", "brd","+","dev",$dev,"label",$label) == 0) 
    {
        system("arping","-q","-A","-c","1","-I",$dev,$vip);
        print "INFO: brought up $vip on $dev label $label\n";
    } else {
        print "ERROR: $!\n";
    }
}


sub ospfd_installed {
	foreach (@services) {
		unless (-d $_) {
			print "ERROR: Missing -d $_\n";
			return 0;
		}
	}

        foreach (@vtyshs) {
	        if  (-x $_) {
		        $vtysh = $_;
		        return 1;
                }
	}
	print "ERROR: Missing -x ", join ' or ', @vtyshs, "\n";
	return 0;
}

sub ospfd_running {
	my $test = `$vtysh -c "show ip ospf"`;
	print $test;
	if ($test =~ m/area/ig) {
		print "ospfd is answering\n";
		return 1;
	} else {
		print "ospfd not is answering\n";
		return 0;
	}
}

sub ospfd_start {
	if (ospfd_running()) {
		print "ospfd running; not starting services\n";
	} else {
		print "starting services: @services\n";
		$ENV{"PATH"} = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
		print "svc -ut @services\n";
		system("svc -ut @services");
	}
}

sub vip_up_loopback {
    my ($vip, $label) = @_;

	# This routine uses L3 switching and OSPF and zebra/ospfd
	# this means netmasks are a bit different
	# and we don't get arp colisions - so use fping.
	# no gratuitious arp either
	# if zebra/ospfd are found, but not running, kick them
	# (do this by using vtysh)
    print "called vip_up_loopback(@_)\n";

    unless (ospfd_installed()) {
        print "ERROR: ospfd is not installed, we can NOT do this.\n";
	exit 1;
    }

    my $dev = $label;
    $dev =~ s/:\d+$//;
    my $ls_dev = `ip addr ls dev $dev 2>&1`;
    chomp $ls_dev;
    die "ERROR: $ls_dev\n" if $?;

    # Verify that the interface is not up
    interfaceUp($ls_dev, $label) and
        die "ERROR: interface '$label' is already up.\n";

    # Duplicate address detection: send 1 probe and wait for 1 sec
    system("fping","-q","-c","2",$vip);
    die "ERROR: Some host already uses $vip\n" unless $?;

    my $netmask = "32";
    print "INFO: bringing up $vip on $dev label $label\n";
    if (system("ip", "addr", "add", "$vip/$netmask", "brd","+","dev",$dev,"label",$label) == 0) 
    {
        # Gratuitious arp system("arping","-q","-A","-c","1","-I",$dev,$vip);
	ospfd_start();
        print "INFO: brought up $vip on $dev label $label\n";
    } else {
        print "ERROR: $!\n";
    }
}



# returns the interface used by the IP passed as an argument
sub getLabel {
    my $ip = shift;
    my $label;
    open IP, "ip addr ls|" or die "ip addr ls: $!";
    while (<IP>) {
        next unless /\b$ip\b/o;
        $label = (split)[-1];
        last;
    }
    close IP;

    # untaint
    if ($label) {
            $label =~ /^(.*)$/;
            return $1;
    }
    return;
}

sub vip_down {
    my $vip = shift;
    my $label = getLabel($vip);
    die "ERROR: could not find interface for $vip\n" unless $label;
    my $dev = $label; $dev =~ s/:\d+$//;

    print "INFO: bringing down $vip from $dev label $label\n";
    if (system("ip","-f","inet","addr","del","dev",$dev,"label",$label) == 0) {
        print "INFO: brought down $vip from $dev label $label\n";
    } else {
        print "ERROR: $!\n";
    }
}

__END__

=head1 NAME

linux_vip.pl - Brings a vip up or down on this machine

=head1 SYNOPSIS

linux_vip.pl [options] <vip> (up|down) [interface]

 Options:
    --help          full documentation

=cut
