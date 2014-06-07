package Seco::Jumpstart::Logger;

use strict;
use warnings;
use Carp;

our $global_logger;
our %verbose = (
    'debug'   => 3,
    'info'    => 2,
    'warning' => 1,
    'warn'    => 1,
    'error'   => 0
);
our %rev_verbose = reverse %verbose;

sub getLogger {
    my ($class) = @_;
    $global_logger = $class->new unless $global_logger;
    return $global_logger;
}

sub new {
    my ($class) = @_;
    my $self = { 'level' => 1 };
    return bless $self, $class;
}

sub convertLevel {
    my $level = shift;
    if (exists $verbose{$level}) {
        $level = $verbose{$level};
    }
    elsif ($level !~ /^\d+$/) {
        confess "Level '$level' unknown";
    }
    return $level;
}

sub setVerbose {
    my ($self, $level) = @_;
    $self->{'level'} = convertLevel($level);
}

sub log {
    my ($self, $level, $msg) = @_;
    $level = convertLevel($level);

    if ($level <= $self->{'level'}) {
        print "\U$rev_verbose{$level}\E: $msg\n";
    }
}

1;
