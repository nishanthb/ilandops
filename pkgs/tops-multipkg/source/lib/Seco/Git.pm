package Seco::Git;

# created at : 2013-03-21 15:56:19
# author     : Jianing Yang <jianingy.yang AT gmail DOT com>

use strict;
use base qw(Seco::Class);

use File::Copy qw(copy);
use File::Temp qw/tempfile tempdir/;
use Cwd;
use Getopt::Long qw/:config require_order gnu_compat/;
use Git;

BEGIN {
    __PACKAGE__->_accessors(branch => undef,
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

# Clone the source repository to a local directory
sub clone {
    my ($repo, $target, $opts) = @_;
    info("Cloning from $repo to $target");
    my $out = Git::command('clone', '-b', $opts->{B}, $repo, $target);
    info($out);
}

sub pull {
    my $self = shift;
    my $repo = shift;

    my $basedir = $self->tmpdir . "/build";
    mkdir $basedir unless(-d $basedir);

    my $target = $self->depositdir . '/source';
    my $out = Git::command('clone', '-b', $self->branch, $repo, $target);

    return { sourcedir => $target };
}

1;
