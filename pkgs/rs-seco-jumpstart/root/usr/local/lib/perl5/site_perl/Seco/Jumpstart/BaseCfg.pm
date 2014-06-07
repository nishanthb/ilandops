package Seco::Jumpstart::BaseCfg;

use strict;
use warnings;
no warnings 'deprecated';
use fields qw/logger_/;
use Seco::Jumpstart::Logger;

sub new {
    my __PACKAGE__ $self = $_[0];

    unless (ref $self) {
        $self = fields::new($self);
    }
    $self->{logger_} = Seco::Jumpstart::Logger->getLogger; 
    return $self;
}

sub log {
    my __PACKAGE__ $self = shift;
    my ($level, $msg) = @_;
    $self->{logger_}->log($level, $msg);
}

1;
