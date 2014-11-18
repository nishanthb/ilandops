#!/usr/local/bin/perl -w

use 5.006;
use strict;
use warnings;

use lib "/jumpstart/lib";
use Seco::Jumpstart;
use Seco::Jumpstart::HostConfig;
use Seco::Jumpstart::Utils qw/:all/;
use Seco::Jumpstart::Bootloader;
use Seco::Jumpstart::Raid;
use Seco::Jumpstart::Disk;
use Seco::Jumpstart::Network;
use Seco::Jumpstart::HW_Checks;

use YAML;

my $host_config = Seco::Jumpstart::HostConfig->instance;
my $jumpstart = Seco::Jumpstart->new($host_config);
$jumpstart->prepare;

$jumpstart->should_i_jump;

installstep('Hardware checks');
my $testing = Seco::Jumpstart::HW_Checks->new($host_config);
$testing->test_cpu or crapout("CPU test failed: $testing->{msg}");
$testing->test_memory or crapout("Memory test failed: $testing->{msg}");
$testing->test_ipmi or crapout("IPMI test failed: $testing->{msg}");

installstep('ntpdate');
$jumpstart->ntpdate;

installstep('Disk configuration (including raid)');

my $type;
 if(my $disk = Seco::Jumpstart::Disk->new($host_config)) {
     $disk->setup_raids;
     $testing->test_disk or crapout("Disk test failed: $testing->{msg}");
     $disk->setup_rest;
 } else {
     my $raid = Seco::Jumpstart::Raid->new($host_config);
   
     if($raid->test_before_raid) {
 	$testing->test_disk or crapout("Disk test failed: $testing->{msg}");
 	$raid->setup;
     } else {
 	$raid->setup;
 	$testing->test_disk or crapout("Disk test failed: $testing->{msg}");
     }
     $type = 'raid';
 }

installstep('imaging');
$jumpstart->image_root;

installstep('mounting');
$jumpstart->mount_newroot;

installstep('check_fslayout');
$jumpstart->check_fslayout;

installstep('make_symlinks');
$jumpstart->make_symlinks;

installstep('fix_etc');
$jumpstart->fix_etc;

if($type eq 'raid') {
    installstep('fix_fstab');
    $jumpstart->fix_fstab;
}

my $network = Seco::Jumpstart::Network->new($host_config);

installstep('network');
$network->setup;
$jumpstart->fix_modprobe;
$jumpstart->copy_mtab;

#XXX:(yuting): we dont generate repo conf, use tempalte default.
# $jumpstart->generate_repo_conf;

#XXX:(yuting): no dnslog user .
#installstep('throw dnslog into passwd');
#$jumpstart->passwd_dnslog;

if($host_config->get('etch_host')) {
    installstep('installing etch');
    $jumpstart->etch_resolv_conf;
    $jumpstart->install_etch;
    system("killall -9 rpcd");
    system("killall -9 sshd-2222");
    system("killall -9 sshd");
    system("killall -9 codautil");
    system("killall -9 snmpd");
    system("killall -9 syslogd");
    system("killall -9 klogd");
} else {
    unless ($host_config->is('gemclient_host')) {
        installstep('installing custom packages');
        $jumpstart->custom_packages;
    } else {
        installstep('install gemstone');
        $jumpstart->install_gemstone;
    }
}

$jumpstart->disable_daemons;

installstep('make more cciss devs');
$jumpstart->make_more_cciss_devs;
installstep('resolv.conf');
$jumpstart->resolv_conf;
installstep('serial ports');
$jumpstart->serials;
installstep('fix motd');
$jumpstart->fix_motd;
installstep('random fixes');
$jumpstart->random_fixes;

installstep('install kernel');
$jumpstart->install_kernel;
installstep('update overrides');
$jumpstart->update_overrides;

installstep('extra modules');
$jumpstart->extra_modules;

my $bootloader = Seco::Jumpstart::Bootloader->new($host_config);
installstep('install bootloader');
$bootloader->install;

installstep('configure next PXE');
$jumpstart->configure_nextboot;

installstep('Unmount new root');
$jumpstart->unmount_newroot;
unless($host_config->get('etch_host')) {
  installstep('fsck new root');
  $jumpstart->fsck_newroot;
}

figlet("Jumpstart Completed");

$jumpstart->reboot;
sleep 30;
exit 0;
