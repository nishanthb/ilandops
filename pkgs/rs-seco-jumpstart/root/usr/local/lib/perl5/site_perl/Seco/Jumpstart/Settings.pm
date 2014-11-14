package Seco::Jumpstart::Settings;

use strict;
use warnings qw/all/;
use constant CF_DIR => "/usr/local/jumpstart/conf";
use Seco::Jumpstart::KernelsCfg;
use Seco::Jumpstart::JS_Utils qw/read_file/;

use base 'Seco::Jumpstart::BaseCfg';
use fields qw/label based_on overrides cache_/;

my %valid_settings_ = map { $_ => 1 } qw/
  serial-port serial-speed serial-parity serial-bits
  software-raid scsi-disks ide-disks fs-layout
  hardware-raid etch-host freebsd-host nfs-root-path
  motd-tag root-disk-img default-fs kernel
  installer-kernel rhel4-update-level
  template-dir cpus root-path
  hyperthreading
  memory hp-smartarray root-partition
  eth0-mtu eth1-mtu eth2-mtu
  nmi-watchdog kernel-append
  ramdisk-size tigon3-module
  raid-chunk-size
  min-disk-speed zapsector-threads
  installer-img
  installer-script
  package-installer
  bootloader
  ipmi-enabled
  initrd
  pxe-style
  elevator
  enforce-yst-layout
  kickstart
  domain-name
  domain-name-servers
  nfs-home
  gemclient-host
  install-packages
  after-install-command
  pxelinux
  tftp-server
  /;

#  XXX: move from qw()
#  sysbuilder


sub valid_setting {
    my $setting = $_[1];
    return exists $valid_settings_{$setting} || $setting eq 'based-on';
}

# all group settings
my %settings_;

my $kernel_cfg_;

sub kernel_cfg_init {
    $kernel_cfg_ = Seco::Jumpstart::KernelsCfg->new unless $kernel_cfg_;
}

sub new {
    my ($class, $label, @based_on) = @_;

    kernel_cfg_init();
    @based_on = qw/DEFAULT/ unless @based_on;
    my $based_on = [ reverse @based_on ];

    my __PACKAGE__ $self = fields::new($class);
    $self->SUPER::new;

    $self->{label}     = $label;
    $self->{based_on}  = $based_on;
    $self->{overrides} = {};
    $self->{cache_}    = {};

    $self->register;
    return $self;
}

sub register {
    my $self  = shift;
    my $label = $self->{label};
    $settings_{$label} = $self;
}

sub overrides {
    my __PACKAGE__ $self = shift;
    my $ref_settings     = shift;
    my %h                = %$ref_settings;
    my $base             = $h{'based-on'};
    if ($base) {
        my @based_on = reverse split /[\s,]+/, $base;
        $self->{'based_on'} = \@based_on;
        for my $b (@based_on) {
            $self->log('warn', "Unknown config: $b")
              unless $settings_{$b};
        }

        delete $h{'based-on'};
    }
    $self->{'overrides'} = \%h;
}

sub get {
    my __PACKAGE__ $self = shift;
    my ($setting) = @_;
    $self->log("warning", "Unknown setting: $setting")
      unless $valid_settings_{$setting};
    my $cache = $self->{cache_};

    return $cache->{$setting} if exists $cache->{$setting};
    if (defined $self->{'overrides'}{$setting}) {
        $cache->{$setting} = $self->{'overrides'}{$setting};
        return $cache->{$setting};
    }

    my @search_parents = @{ $self->{'based_on'} };
    my $result;

    # FIXME Need to check for base-on already visited
    for my $l (@search_parents) {

        #print "DEBUG: $l\n";
        $result = $settings_{$l}->{overrides}{$setting};
        if (defined $result) {
            $cache->{$setting} = $result;
            return $result;
        }
        else {
            my $gp = $settings_{$l}->{based_on};
            if ($gp) {
                for my $parent (@$gp) {
                    next if $parent eq "DEFAULT";
                    push @search_parents, $parent;
                }
            }
        }
    }

    # OPSDB here?

    $result = $settings_{'DEFAULT'}->{overrides}{$setting};
    die "DEFAULT didn't provide a setting for $setting" unless defined $result;

    $cache->{$setting} = $result;
    return $result;
}

sub get_kernel_name {
    my __PACKAGE__ $self = shift;
    my ($name)           = @_;
    my $kernel           = $self->get($name);
    my $result           = $kernel_cfg_->kernel_name($kernel);
    return $result;
}

sub kernel_name {
    my __PACKAGE__ $self = shift;
    return $self->get_kernel_name("kernel");
}

sub i_kernel_name {
    my __PACKAGE__ $self = shift;
    return $self->get_kernel_name("installer-kernel");
}

sub kernel_pkgname {
    my __PACKAGE__ $self = shift;
    my $kernel           = $self->kernel_name;
    my $replacement      = 'kernel';
    $kernel =~ s/^vm(linuz)?/$replacement/;
    return $kernel;
}

sub disk_config {
    my __PACKAGE__ $self = shift;
    my $fs_layout        = $self->get("fs-layout");
    my $layout           = read_file(CF_DIR . "/fs/$fs_layout");
    return $layout;
}

sub root_disk {
    my __PACKAGE__ $self = shift;
    my $ide = $self->get("ide-disks");
    $ide = 0 if $ide eq '*';
    my $hp = lc($self->get("hp-smartarray"));
    return $ide > 0 ? "hda" : $hp ne "no" ? "cciss/c0d0" : "sda";
}

sub root_partition {
    my __PACKAGE__ $self = shift;
    my $ide = $self->get("ide-disks");
    $ide = 0 if $ide eq '*';
    my $hp = lc($self->get("hp-smartarray"));
    return $self->get('root-partition')
      if ($self->get('root-partition') =~ /^md\d/);
    return $ide > 0 ? "hda1" : $hp ne "no" ? "cciss/c0d0p1" : "sda1";
}

sub serial {
    my __PACKAGE__ $self = shift;
    my $port = $self->get('serial-port');
    return "no" if $port eq "no";

    return sprintf("ttyS%d,%d%s%d",
        $port,
        $self->get('serial-speed'),
        $self->get('serial-parity'),
        $self->get('serial-bits'));
}

sub template_dirs {
    my __PACKAGE__ $self = shift;
    my $template_dir = $self->get("template-dir");
    my @dirs = map { "/profiles/profile.d/$_" } split(' ', $template_dir);
    return join(" ", @dirs);
}

sub dump {
    my $self     = shift;
    my @based_on = reverse @{ $self->{based_on} };
    print "    based-on = ", join(",", @based_on), "\n" if @based_on;
    my %settings = %{ $self->{overrides} };
    for my $setting (sort keys %settings) {
        print "    $setting = ", $settings{$setting}, "\n";
    }
}

1;
