package Seco::Jumpstart::FirstBoot;

use strict;
use warnings 'all';
use Carp;
use File::Path;
use Seco::Jumpstart::JS_Utils qw/read_file write_file WWWDATA/;

sub new {
    confess "Don't call new on FirstBoot, use the get method.";
}

sub get {
    my ($class, $node) = @_;
    my $dir = "/JumpStart/hosts/" . substr($node, -2) . "/$node/firstboot";
    return unless -d $dir;
    my $mode = read_file("$dir/mode");
    return unless $mode;
    my $timestamp = (stat("$dir/mode"))[9];
    my $user      = read_file("$dir/user");
    chomp($mode, $user);
    return ($mode, $timestamp, $user);
}

sub set {
    my ($class, $node, $mode, $user) = @_;
    $user ||= "root";
    my $dir = "/JumpStart/hosts/" . substr($node, -2) . "/$node/firstboot";
    unless (-d $dir) {
        mkpath($dir);
        my ($uid, $gid) = (getpwnam(WWWDATA))[ 2, 3 ];
        my $base = "/JumpStart/hosts/" . substr($node, -2);
        chown $uid, $gid, $dir, $base, "$base/$node";
    }
    write_file("$dir/mode", "$mode\n");
    write_file("$dir/user", "$user\n");
}

1;
