package Seco::Jumpstart::PxeEntry;

use strict;
use warnings 'all';

use Seco::Jumpstart::KernelsCfg;
use fields qw/group js/;

sub new {
    my ($class, $group, $js) = @_;
    my __PACKAGE__ $self = fields::new($class);
    $self->{group} = $group;
    $self->{js}    = $js;

    return $self;
}

sub generate {
    my __PACKAGE__ $self = shift;
    my ($fh)             = @_;
    my $js               = $self->{js};
    unless ($js->get('kickstart') eq 'yes') {

        # normal js style pxe
        $self->generate_js($fh);
    }
    else {
        $self->generate_ks($fh);
    }
}

sub generate_ks {
    my __PACKAGE__ $self = shift;
    my ($fh)             = @_;
    my $js               = $self->{js};
    my $group            = $self->{group};
    my $console          = $js->get('serial-port');
    $console = "console=ttyS$console";

    print $fh <<EOT;
LABEL $group-I
 KERNEL vmlinuz.AS4-U0-i386
 APPEND ksdevice=eth0 $console load_ramdisk=1 initrd=initrd.img-AS4-U0-i386 network devfs=nomount ks=http://yum/kickstart/installnet3/ks.RHEL4_x86_eth0.generated

LABEL $group-N
 KERNEL vmlinuz.AS4-U0-i386
 APPEND initrd=initrd.img-AS4-U0-i386 $console

LABEL $group-E
 KERNEL vmlinuz.AS4-U0-i386
 APPEND initrd=initrd.img-AS4-U0-i386 $console

EOT

}

sub get_console {
    my __PACKAGE__ $self = shift;
    my $js               = $self->{js};
    my $serial           = $js->serial;
    my $console = $serial eq "no" ? "" : "console=tty0 console=$serial";

    return $console;
}

# For a given group (aka profile name) we need to generate
# 3 entries: (normal, install, emergency)
sub generate_js {
    my __PACKAGE__ $self = shift;
    my ($fh)             = @_;
    my $group            = $self->{group};
    my $js               = $self->{js};
    my $console          = $self->get_console;
    my $fs               = $js->get('default-fs');
    my $rootpart         = $js->root_partition;
    my $kernel           = $js->kernel_name;
    my $pxe_style        = $js->get('pxe-style');
    my $elevator_val     = $js->get('elevator');
    my $initrd           = $js->get('initrd');
    if ($initrd eq 'DEFAULT') {
        $initrd = $kernel;
        for ($initrd) {
            s/vmlinuz/i/;
            s/vm-/i-/;
        }
    }
    my $ikernel       = $js->i_kernel_name;
    my $nmi_val       = $js->get('nmi-watchdog');
    my $nmi           = $nmi_val ? "nmi_watchdog=$nmi_val" : "";
    my $kernel_append = $js->get('kernel-append');
    if ($kernel_append =~ /"([^"]*)"/) {
        $kernel_append = $1;
    }
    my $ramdisk_size  = $js->get('ramdisk-size');
    my $installer_img = $js->get('installer-img');

    print $fh <<EOF;
LABEL $group-I
 KERNEL $ikernel
 APPEND initrd=$installer_img root=0100 rw ramdisk_size=524288 Jump=$group hostname=foo init=/j panic=30 $console $nmi
 IPAPPEND 1

EOF

    my $INITRD = '';
    if ($pxe_style eq 'debian') {
        $INITRD = "initrd=$initrd ramdisk_size=$ramdisk_size fs=$fs"
          if lc($initrd) ne 'no';
        print $fh <<EOF;
LABEL $group-N
 KERNEL $kernel
 APPEND root=/dev/$rootpart panic=30 $INITRD $console $nmi $kernel_append

LABEL $group-E
 KERNEL $kernel
 APPEND root=/dev/$rootpart panic=30 init=/bin/sh $console $kernel_append

EOF
    }
    elsif ($pxe_style eq 'redhat') {
        $INITRD = "initrd=$initrd fs=$fs"
          if lc($initrd) ne 'no';
        my $elevator = "elevator=$elevator_val";
        print $fh <<EOF;
LABEL $group-N
 KERNEL $kernel
 APPEND root=/dev/$rootpart panic=10 $INITRD $console $elevator $nmi $kernel_append

LABEL $group-E
 KERNEL $kernel
 APPEND root=LABEL=/ panic=10 $INITRD init=/bin/sh $console $kernel_append

EOF
    }
    else {
        die "ERROR: Unknown pxe_style: $pxe_style";
    }
}

1;
