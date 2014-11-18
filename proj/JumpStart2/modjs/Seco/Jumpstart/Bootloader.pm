package Seco::Jumpstart::Bootloader;

use 5.006;
use strict;
use warnings 'all';
use Seco::Jumpstart::Utils qw(:all);

our $VERSION = '1.0.0';

sub parse_template {
    my $self = shift;
    my $cfg = $self->{cfg};
    my $config = shift;
    
    my $bootdevice = $cfg->get('bootdevice');
    my $bootdisk = $cfg->get('bootdisk');
    my $bootpartition;
    
    if($bootdevice) {
        $bootdisk = $bootdevice;
        $bootdisk =~ s/p?(\d+)$//;
        $bootpartition = $1 - 1;
    } if(!$bootdevice) {
        $bootdevice = "/dev/" . $bootdisk . "1";
        $bootdisk =~ s/p?(\d+)$//;
        $bootpartition = $1 - 1;
    }
    
    my $serial_port = $cfg->get('serial_port');
    my $serial_bits = $cfg->get('serial_bits');
    my $serial_speed = $cfg->get('serial_speed');
    my $serial_parity = $cfg->get('serial_parity');
    
    my ($kernel, $initrd) = ('/vmlinuz', '/initrd.img');
    if($cfg->get('package_installer') eq 'yum') {
        my $kernel = $cfg->get('kernel_package');
        
        $kernel =~ s/^kernel-/\/boot\/vmlinuz-/;
        $kernel =~ s/smp//;
        
        my $initrd = $kernel;
        $initrd =~ s/vmlinuz/initrd/;
    }
    
    my %subs = ( DISK => $bootdisk,
                 DEVICE => $bootdevice,
                 SERIAL_PORT => $serial_port,
                 SERIAL_SPEED => $serial_speed,
                 SERIAL_SPEED_PARITY => $serial_speed . lc($serial_parity) .
                 $serial_bits,
                 KERNEL => $kernel,
                 INITRD => $initrd,
                 BOOTPARTITION => $bootpartition
               );
    
    $config =~ s/__(\w+)__/defined($subs{$1}) ? $subs{$1} : $1/ge;
    return $config;
}

sub new {
    my ($class, $cfg) = @_;
    
    my $self = { cfg => $cfg };
    bless $self, $class;
}

sub install {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    my $bootloader = $cfg->get('bootloader');
    return $self->install_lilo if $bootloader eq 'lilo';
    return $self->install_grub if $bootloader eq 'grub';
    crapout("I don't know how to install $bootloader");
}

sub install_lilo {
    my $self = shift;
    
    my $liloconfig = <<EOF;
lba32
boot=__DISK__
root=__DEVICE__
install=/boot/boot.b
map=/boot/map
delay=50
vga=normal
default=Linux
serial=__SERIAL_PORT__,__SERIAL_SPEED_PARITY__

image=__KERNEL__
    label=Linux
    append="console=ttyS__SERIAL_PORT__,__SERIAL_SPEED__"
    read-only

EOF
    
    my $newconfig = $self->parse_template($liloconfig);
    write_file('/mnt/etc/lilo.conf', $newconfig);
    run_local(qw{chroot /mnt /sbin/lilo});
}

sub install_grub {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    my $grubconfig = <<EOF;
default=0
timeout=5
serial --unit=__SERIAL_PORT__ --speed=__SERIAL_SPEED__
terminal --timeout=5 serial console
title Default Kernel
  root (hd0,__BOOTPARTITION__)
  kernel /boot/boot-kernel root=__DEVICE__ console=ttyS__SERIAL_PORT__,__SERIAL_SPEED__
  initrd /boot/boot-initrd
EOF
    
    my $devmap = <<EOF;
(hd0)	__DISK__
EOF
    
    if($cfg->get('package_installer') eq 'yum') {
        my $kernel = $cfg->get('kernel_package');

	#XXX:(yuting): sian kernel debug soa kernel replace
	#XXX:(yuting): rule. only for x86_64
	if ($kernel =~ /kernel-debug/ ) {
	    for($kernel) {
		s{^kernel-debug-}{/boot/vmlinuz-};
		s/\.x86_64$/\.x86_64.debug/;
	    }
	} else {
	    for ($kernel) {
		s{^kernel-}{/boot/vmlinuz-};
		s/-(64|32)$//;
		s/\.RH$/.ELsmp/;
		s/-22\.34\./-34./;
	    }
	}
 
        my $initrd = $kernel;
	if($kernel =~ /\.x86_64\.debug$/) {
	    $initrd =~ s/vmlinuz/initramfs/;
	    $initrd = "$initrd.img";
	} else {
	    $initrd =~ s/vmlinuz/initrd/;
	    $initrd = "$initrd.img";
	}
 
        System("ln -sfn $kernel /mnt/boot/boot-kernel");
        System("ln -sfn $initrd /mnt/boot/boot-initrd");
    }
    
    write_file('/mnt/boot/grub/device.map', $self->parse_template($devmap));
    write_file('/mnt/boot/grub/grub.conf', $self->parse_template($grubconfig));
    System("chroot /mnt grub-install hd0");
}

1;
