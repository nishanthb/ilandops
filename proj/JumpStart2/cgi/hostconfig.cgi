#! /usr/local/bin/perl -w
use strict;
use warnings 'all';
use CGI;
use YAML;
use Seco::Jumpstart::NextBoot;
use Seco::Jumpstart::HostRecord;
use Seco::Jumpstart::Overrides;

my $q = CGI->new;
print $q->header("text/plain");

my $name = $q->param('hostname') || 'ordeal';

for ($name) {
    s/.inktomisearch.com$//;
    s/.yst.corp.yahoo.com$//;
    s/.inktomi.com$//;
}

my $hr = Seco::Jumpstart::HostRecord->get($name);

unless ($hr->admin) {
    print "EMPTY HOST RECORD!\n";
    exit;
}

my $cfg_hr = Load($hr->yaml_hostrecord(Seco::Jumpstart::NextBoot->get($name)));
my $prof_hr = parse_profile($cfg_hr->{'profile'});
my $serial_port = Seco::Jumpstart::Overrides->get($name, "serial-port");
if (defined $serial_port) {
    $prof_hr->{'serial_port'} = $serial_port;
}

my $cfg = flatten($cfg_hr, $prof_hr);
print Dump($cfg);

# THIS SUCKS SO BAD
sub parse_profile {
    my $profile = shift;
    my $yaml_file = "/JumpStart/profiles/$profile.yaml";
    unless (-r $yaml_file) {
        print "$yaml_file: does not exist\n";
        return;
    }
    my $yaml = YAML::LoadFile($yaml_file);
    my $installer_script = $yaml->{installer_script};
    my $diskimage = $yaml->{disk_image};
    my $etcdir = $yaml->{template_dir};
    my $motd_tag = $yaml->{motd_tag};
    my $eth0_mtu = $yaml->{eth0_mtu};
    my $eth1_mtu = $yaml->{eth1_mtu};
    my $eth2_mtu = $yaml->{eth2_mtu};
    my $nfs_home = $yaml->{nfs_home};
    my $kernel_package = $yaml->{kernel_pkg};
    my $tigon3_module = $yaml->{tigon3_module};
    my $raid_chunk_size = $yaml->{raid_chunk_size};
    my $min_disk_speed = $yaml->{min_disk_speed};
    my $package_installer = $yaml->{package_installer};
    my $bootloader = $yaml->{bootloader};
    my $serial_port = $yaml->{serial_port};
    my $serial_speed = $yaml->{serial_speed};
    my $serial_bits = $yaml->{serial_bits};
    my $serial_parity = $yaml->{serial_parity};
    my $enforce_yst_layout = $yaml->{enforce_yst_layout};
    my $diskconfig = $yaml->{disk_config};
    my $etch_host = $yaml->{etch_host};
    my $rhel4_update_level = $yaml->{rhel4_update_level};
    my $gemclient_host = $yaml->{gemclient_host};
    my $install_packages = $yaml->{install_packages};
    my $after_install_command = $yaml->{after_install_command};
    my $zapsector_threads = $yaml->{zapsector_threads};

    my %res = (
        installer_script => $installer_script,
        diskimage => "http://boothost/tftpboot/$diskimage",
        etcdir => $etcdir,
        motd_tag => $motd_tag,
        eth0_mtu => $eth0_mtu,
        eth1_mtu => $eth1_mtu,
        eth2_mtu => $eth2_mtu,
        nfs_home => $nfs_home,
        gemclient_host =>  $gemclient_host,
        install_packages => $install_packages,
        after_install_command => $after_install_command,
        kernel_package => $kernel_package,
        tigon3_module => $tigon3_module,
        raid_chunk_size => $raid_chunk_size,
        min_disk_speed => $min_disk_speed,
        package_installer => $package_installer,
        etch_host => $etch_host,
        rhel4_update_level => $rhel4_update_level,
        bootloader => $bootloader,
        serial_port => $serial_port,
        serial_bits => $serial_bits,
        
        serial_parity => $serial_parity,
        serial_speed => $serial_speed,
        enforce_yst_layout => $enforce_yst_layout,
        zapsector_threads => $zapsector_threads,
        diskconfig => [split "\n", $diskconfig]);

    return \%res;
}

sub flatten {
    my ($hr1, $hr2) = @_;

    my %h = (%$hr1, %$hr2);
    return \%h;
}

