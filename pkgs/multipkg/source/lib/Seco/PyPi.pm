package Seco::PyPi;

# created at : 2013-03-21 15:56:19
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

    my $target = $self->depositdir . '/source';
    my $index = "https://pypi.python.org/pypi/$name/$version/json";

    eval { require JSON; };
    die "JSON required to install pypi modules" if ($@);

    my $json = qx(curl -s '$index');
    my $pypi = JSON->new->utf8->decode($json);
    my $ver = 'UNKNOWN';

    $version = $pypi->{info}->{version}
      unless $version;

    foreach my $pkg (@{$pypi->{urls}}) {
       next if $pkg->{url} !~ /(\.tar\.gz|\.tar\.bz2|\.tar\.xz|\.tgz)$/;

       my $suffix = $1;
       my $url = $pkg->{url};
       my $tarball = $self->depositdir . '/source' . $suffix;
       my $xfercmd = $self->xfercmd;

       $xfercmd =~ s/%s/$tarball/;
       $xfercmd =~ s/%u/$url/;

       system($xfercmd); 

       return { sourcetar => $tarball,
                version   => $version };

    }

    undef;
}

1;
