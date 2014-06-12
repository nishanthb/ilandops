package Seco::Jumpstart::Group;

use strict;
use warnings 'all';

use File::Path;
use Carp;
use YAML ();
use constant LILOCONFIG_FILE => "/usr/local/jumpstart/templates/liloconfig";
use constant PROFILE_FILE    => "/usr/local/jumpstart/templates/profile";
use constant JS              => "/usr/local/jumpstart";
use Seco::AwesomeRange qw/:all/;

use Seco::Jumpstart::Settings;
use Seco::Jumpstart::KernelsCfg;
use Seco::Jumpstart::JS_Utils qw/get_ip fqdn read_file WWWDATA/;
use Seco::Jumpstart::EthersCfg;
use Seco::Jumpstart::PxeEntry;
use Seco::Jumpstart::HostRecord;

use base 'Seco::Jumpstart::BaseCfg';
use fields qw/label settings range ethers/;

sub new {
    my ($class, %vals) = @_;
    my __PACKAGE__ $self = fields::new($class);

    $self->SUPER::new;
    $self->{label}    = $vals{label};
    $self->{settings} = Seco::Jumpstart::Settings->new($self->{label});
    $self->{ethers}   = Seco::Jumpstart::EthersCfg->instance;

    $self->{range} = [ expand_range($vals{range}) ];
    $self->{'settings'}->overrides($vals{'settings'});
    return bless $self, $class;
}

sub settings {
    my __PACKAGE__ $self = shift;
    return $self->{settings};
}

sub count {
    my __PACKAGE__ $self = shift;
    return scalar @{ $self->{range} };
}

sub good_ip {
    my ($copy) = @_;
    my $ip = get_ip($copy);
    $_[0] = $copy;
    defined($ip) and $ip ne "0.0.0.0";
}

sub dump {
    my __PACKAGE__ $self = shift;
    my $valid_only = shift;
    print $self->{label}, "\n";
    $self->{settings}->dump;
    my @range = @{ $self->{range} };
    if ($valid_only) {
        @range = grep { good_ip($_) } @range;
    }

    print "    INCLUDE ", compress_range(\@range), "\n";
}

#
{
    my %labels_nodes;

    sub update {
        my __PACKAGE__ $self = shift;
        my $label = $self->{'label'};
        for my $node (@{ $self->{range} }) {
            if ($labels_nodes{$node}) {
                $self->log('error',
"$node belongs to more than one group ($labels_nodes{$node}, $label)"
                );
            }
            my $hr = Seco::Jumpstart::HostRecord->get($node);
            $hr->label($self->{'label'});
            $labels_nodes{$node} = $label;
        }
    }

    sub get_label {
        my ($class, $node) = @_;
        return $labels_nodes{$node};
    }
}

sub pxe_entry {
    my __PACKAGE__ $self = shift;
    my ($fh, $group) = @_;

    my $js = $self->{'settings'};
    my $pxe_entry = Seco::Jumpstart::PxeEntry->new($group, $js);
    $pxe_entry->generate($fh);
}

sub create_profile {
    my __PACKAGE__ $self = shift;
    my ($filename) = @_;

    my $js   = $self->{'settings'};
    my %subs = (
        GROUP_NAME       => $self->{label},
        GEMCLIENT_HOST   => $js->get('gemclient-host'),
        INSTALL_PACKAGES => [ split '\s*;\s*', $js->get('install-packages') ],
        AFTER_INSTALL_COMMAND => $js->get('after-install-command'),
        NFS_HOME              => $js->get('nfs-home'),
        DISK_IMAGE            => $js->get('root-disk-img'),
        LILO_CONFIG           => $self->gen_lilo_config,
        DISK_CONFIG           => $js->disk_config,
        TEMPLATE_DIR          => $js->template_dirs,
        MOTD_TAG              => $js->get('motd-tag'),
        ETH0_MTU              => $js->get('eth0-mtu'),
        ETH1_MTU              => $js->get('eth1-mtu'),
        ETH2_MTU              => $js->get('eth2-mtu'),
        TIGON3_MODULE         => $js->get('tigon3-module'),
        MIN_DISK_SPEED        => $js->get('min-disk-speed'),
        ZAPSECTOR_THREADS     => $js->get('zapsector-threads'),
        RAID_CHUNK_SIZE       => $js->get('raid-chunk-size'),
        INSTALLER_SCRIPT      => $js->get('installer-script'),
        PACKAGE_INSTALLER     => $js->get('package-installer'),
        ETCH_HOST             => $js->get('etch-host'),
        RHEL4_UPDATE_LEVEL    => $js->get('rhel4-update-level'),
        FREEBSD_HOST          => $js->get('freebsd-host'),
        ROOT_PATH             => $js->get('root-path'),
        NFS_ROOT_PATH         => $js->get('nfs-root-path'),
        BOOTLOADER            => $js->get('bootloader'),
        KERNEL_PKG            => $js->kernel_pkgname,
        SERIAL_PORT           => $js->get('serial-port'),
        SERIAL_BITS           => $js->get('serial-bits'),
        SERIAL_SPEED          => $js->get('serial-speed'),
        SERIAL_PARITY         => $js->get('serial-parity'),
        ENFORCE_YST_LAYOUT    => $js->get('enforce-yst-layout'),
    );
    my %yaml;
    while (my ($k, $v) = each %subs) {
        $v =~ s/::(\w+)::/defined($subs{$1}) ? $subs{$1} : $1/ge;
        $yaml{ lc($k) } = $v;
    }

    my $profile = read_file(PROFILE_FILE);
    $profile =~ s/::(\w+)::/defined($subs{$1}) ? $subs{$1} : $1/ge;

    # just in case one sub expands to another
    $profile =~ s/::(\w+)::/defined($subs{$1}) ? $subs{$1} : $1/ge;

    $profile .= "\n# Automatically generated on " . localtime() . "\n";

    open my $fh, ">$filename" or die "$filename: $!";
    print $fh $profile;
    close $fh;

#    $yaml{sysbuilder} = $js->get('sysbuilder');
    YAML::DumpFile("$filename.yaml", \%yaml);
    return;
}

sub gen_lilo_config {
    my __PACKAGE__ $self = shift;
    my $js = $self->{'settings'};

    my %subs = (
        BOOT_DISK      => $js->root_disk,
        ROOT_PARTITION => $js->root_partition,
        SERIAL_PORT    => $js->get('serial-port'),
        SERIAL_SPEED   => $js->get('serial-speed'),
        SERIAL_PARITY  => lc($js->get('serial-parity')),
        SERIAL_BITS    => $js->get('serial-bits'),
    );

    my $liloconfig = read_file(LILOCONFIG_FILE);
    $liloconfig =~ s/::(\w+)::/defined $subs{$1} ? $subs{$1} : "[$1]"/ge;
    return $liloconfig;
}

sub create_host_record {
    my __PACKAGE__ $self = shift;
    my ($node) = @_;

    my $js       = $self->{'settings'};
    my $label    = $self->{label};

    # my $boothost = compress_range(expand_range("bh($node),-$node"));
    my $boothost = compress_range(expand_range("^ $node"));

    my $ip = get_ip($node);
    my $hr = Seco::Jumpstart::HostRecord->get($node);
    #use Data::Dumper;
    #print Dumper($hr);

    $hr->ip($ip);
    $hr->idedisks($js->get('ide-disks'));
    $hr->disks($js->get('scsi-disks'));
    $hr->cpus($js->get('cpus'));
    $hr->softwareraid($js->get('software-raid'));
    $hr->hwraid($js->get('hardware-raid'));
    $hr->def_fs($js->get('default-fs'));
    $hr->hyperthreading($js->get('hyperthreading'));
    $hr->ipmi_enabled($js->get('ipmi-enabled'));
    $hr->memory($js->get('memory'));
    $hr->label($label);
    $hr->macaddr($self->{ethers}->mac($node));
    $hr->admin($boothost);

    #print Dumper($hr);
    $hr->save;
}

sub create_host_records {
    my __PACKAGE__ $self = shift;
    for my $node (@{ $self->{'range'} }) {
        $self->create_host_record($node);
    }
}

my %all;

sub in_gemstone {
    my $node = shift;
    unless (%all) {
        my @all = expand_range('@ALL');
        @all{@all} = undef;
    }

    return exists $all{$node};
}

my @keys;

sub init_keys {
    my $pool = "/export/crawlspace/sshkeypool/keys";
    @keys = glob("$pool/*");
}

sub get_key_from_pool {
    shift @keys;
}

my $dbh;
my $insert = "INSERT INTO skh (node,rsa,dsa) VALUES (?,?,?)";
my $ins_sth;

sub connect_and_prepare {
    $dbh =
      DBI->connect('DBI:Pg:dbname=skh', 'js', 'foobar', { AutoCommit => 0 })
      or die;
    $ins_sth = $dbh->prepare($insert);
}

sub gen_needed_ssh_keys {
    my __PACKAGE__ $self = shift;
    my ($output_dir, $doit) = @_;
    my %not_in_gemstone;

    init_keys() unless @keys;
    my $changes = 0;
    for my $node (@{ $self->{'range'} }) {
        if (not in_gemstone($node)) {
            $not_in_gemstone{$node}++;
            next;
        }
        my $name_with_no_dots = $node;
        $name_with_no_dots =~ s/\..*$//;
        my $node_suffix = substr($name_with_no_dots, -2);
        my $dir         = "$output_dir/$node_suffix";
        my $mod         = 0;
        unless (-d "$dir/$node") {
            unless (-d $dir) {
                mkdir $dir;
                chmod 0700, $dir;
            }
            my $key_from_pool = get_key_from_pool();
            unless ($key_from_pool) {
                $self->log("error", "Out of ssh keys. Need to generate more.");
                die; # hmm maybe we should generate the keys here, but something
                     # is broken and should be fixed.
            }
            my $key = $key_from_pool;
            $key =~ s{/export/crawlspace/sshkeypool/}{};
            $self->log("info", "Taking $key for $node.");
            rename $key_from_pool => "$dir/$node"
              or die "$key_from_pool => $node: $!";

            # modify the comment for the keys
            system(
"cd $dir/$node && perl -pi -e 's/ root.SSHPOOL/ root\\\@$node.inktomisearch.com/' *.pub"
            );
            my $rsa = read_file("$dir/$node/ssh_host_rsa_key.pub");
            my $dsa = read_file("$dir/$node/ssh_host_dsa_key.pub");

            connect_and_prepare() unless $dbh;
            $ins_sth->execute($node, $rsa, $dsa);
            ++$changes;
            ++$mod;
        }

        my $tar_dir = JS . "/skh_tar/$node_suffix";
        if ($mod or not -e "$tar_dir/$node.tar") {
            mkpath($tar_dir) unless -d $tar_dir;
            my $tar_file = "$tar_dir/$node.tar";
            unlink $tar_file;
            my $wwwdata = WWWDATA;
            system(
"cd $dir/$node;tar cf $tar_file .; chown -R $wwwdata .; chmod 755 ."
            );
        }
    }
    if ($changes) {
        $dbh->commit;
    }
    if (%not_in_gemstone) {
        $self->log("debug",
                $self->{label}
              . ": not in gemstone: "
              . compress_range(keys %not_in_gemstone));
    }
    return $changes;
}

END {
    if ($dbh) {
        $ins_sth->finish;
        $dbh->disconnect;
    }
}

1;
