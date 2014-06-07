package Seco::Jumpstart::Overrides;

use strict;
use warnings 'all';
use Carp;
use File::Path;
use Seco::Jumpstart::JS_Utils qw/read_file write_file WWWDATA/;

sub new {
    confess "Don't call new on Overrides, use the accessor methods";
}

sub update {
    my ($class, $node, $field, $value) = @_;
    my $dir = "/JumpStart/hosts/" . substr($node, -2) . "/$node/overrides";
    unless (-d $dir) {
        mkpath($dir);
        my ($uid, $gid) = (getpwnam(WWWDATA))[ 2, 3 ];
        my $base = "/JumpStart/hosts/" . substr($node, -2);
        chown $uid, $gid, $dir, $base, "$base/$node";
    }
    write_file("$dir/$field", "$value\n");
}

sub get {
    my ($class, $node, $field) = @_;
    my $dir = "/JumpStart/hosts/" . substr($node, -2) . "/$node/overrides";
    return undef unless -d $dir;
    return undef unless -r "$dir/$field";
    my $result = read_file("$dir/$field");
    chomp($result);
    return $result;
}

1;
