package Seco::PECL;

# created at : 2013-03-30 18:08:47
# author     : Jianing Yang <jianingy.yang AT gmail DOT com>

use strict;
use base qw(Seco::Class);

use File::Copy qw(copy);
use File::Temp qw/tempfile tempdir/;
use Cwd;
use Getopt::Long qw/:config require_order gnu_compat/;

BEGIN {
    __PACKAGE__->_accessors(xfercmd => undef,
                            depositdir => undef,
                            tmpdir => undef);
    __PACKAGE__->_requires(qw/depositdir/);
}

sub _init {
    my $self = shift;

    mkdir $self->depositdir
      unless(-d $self->depositdir);

    $self->tmpdir(tempdir(CLEANUP => 0))
      unless(-d $self->tmpdir);

    return 1;
}

sub pull {
    my $self = shift;
    my $name = shift;
    my $version = shift;

    my $basedir = $self->tmpdir . "/build";
    mkdir $basedir unless(-d $basedir);

    my $url = "http://pecl.php.net/get/$name/$version";

    my $tarball = $self->depositdir . '/source.tar.gz';
    my $xfercmd = $self->xfercmd;

    $xfercmd =~ s/%s/$tarball/;
    $xfercmd =~ s/%u/$url/;

    system($xfercmd);

    return { sourcetar => $tarball };
}

1;
