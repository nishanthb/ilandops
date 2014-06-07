package Seco::Jumpstart::Perforce;

use strict;
use warnings;

use Sys::Hostname;

use base 'Seco::Jumpstart::BaseCfg';
use fields qw/p4client user port client/;

sub new {
    my ($class) = @_;
    my Perforce $self = fields::new($class);
    $self->SUPER::new;

         $self->{user} = $ENV{P4USER}
      || $ENV{LOGNAME}
      || $ENV{USER}
      || $ENV{SUDO_USER};
    $self->{client} = $ENV{P4CLIENT} || $self->{user} . "." . hostname();
    $self->{port}   = $ENV{P4PORT}   || "juniper.inktomi.com:1666";
    $self->{p4client} = "p4client";
    return $self;
}

sub p4client {
    my Perforce $self = shift;
    my ($p4client) = @_;
    if ($p4client) {
        $self->{p4client} = $p4client;
    }
    return $self->{p4client};
}

sub user {
    my Perforce $self = shift;
    my ($user) = @_;
    if ($user) {
        $self->{user} = $user;
    }
    return $self->{user};
}

sub client {
    my Perforce $self = shift;
    my ($client) = @_;
    if ($client) {
        $self->{client} = $client;
    }
    return $self->{client};
}

sub port {
    my Perforce $self = shift;
    my ($port) = @_;
    if ($port) {
        $self->{port} = $port;
    }
    return $self->{port};
}

sub get_p4_cmd {
    my Perforce $self = shift;
    return sprintf("%s -u %s -c %s -p %s",
        $self->p4client, $self->user, $self->client, $self->port);
}

# return the user who has the file opened or undef
sub opened {
    my Perforce $self = shift;
    my ($file)        = @_;
    my $p4            = $self->get_p4_cmd;
    open my $p4o, "$p4 opened -a $file 2>&1|" or do {
        $self->log("error", "p4 opened: $!");

        return "ERROR";
    };

    my $reply = <$p4o>;
    close $p4o;

    return undef if $reply =~ /not opened anywhere/;
    return (split(' ', $reply))[-1];
}

# FIXME check for errors
sub edit {
    my Perforce $self = shift;
    my ($file)        = @_;
    my $p4            = $self->get_p4_cmd;
    system("$p4 edit $file");
}

sub depot_file {
    my Perforce $self = shift;
    my ($file)        = @_;
    my $p4            = $self->get_p4_cmd;
    open my $p4f, "$p4 files $file 2>&1|" or return undef;
    my $reply = <$p4f>;
    close $p4f;

    $reply =~ s/#\d+.*//;
    return $reply;
}

# FIXME check for errors
sub submit {
    my Perforce $self = shift;
    my ($file, $description) = @_;
    my ($client, $user) = ($self->client, $self->user);
    my $depot_file = $self->depot_file($file);

    my $p4 = $self->get_p4_cmd;
    open my $p4s, "|$p4 submit -i" or return undef;
    print $p4s <<"EOT";
Change: new

Client: $client

User: $user

Status: new

Description:
	$description

Files:
	$depot_file

EOT
    close $p4s;
}

1;
