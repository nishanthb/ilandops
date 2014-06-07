package Seco::Jumpstart::KernelsCfg;

use strict;
use warnings 'all';

use constant KERNELS_CF => "/usr/local/jumpstart/conf/kernels.cf";

use base 'Seco::Jumpstart::BaseCfg';
use fields qw/filename/;
my %kernels;

sub new {
    my ($class, $filename) = @_;

    $filename ||= KERNELS_CF;
    my __PACKAGE__ $self = fields::new($class);
    $self->{filename} = $filename;

    unless (%kernels) {
        $self->load_config;
    }
    return $self;
}

sub kernel_name {
    my __PACKAGE__ $self = shift;
    my ($type) = @_;
    return exists $kernels{$type} ? $kernels{$type} : $type;
}

sub load_config {
    local $/ = "\n";
    my __PACKAGE__ $self = shift;
    my $filename = $self->{filename};

    open my $fh, "<$filename" or die "$filename: $!";
    while (<$fh>) {
        s/#.*$//g;
        s/^\s+//;
        s/\s+$//;
        next unless $_;
        my ($type, $kernel) = split;
        $kernels{$type} = $kernel;
    }
    close $fh;
}

1;

