package Seco::Jumpstart::HostConfig;

use 5.006;
use strict;
use warnings;
use YAML;

use Seco::Jumpstart::Utils qw/:all/;

our $VERSION = "1.0.0";

my $instance;

sub instance {
    return $instance if $instance;
    
    $instance = __PACKAGE__->new_instance;
}

# only 1 copy is needed
sub new {
    &instance;
}
sub new_instance {
    my $class = shift;

    #XXX:(yuting): js-config.yaml here is for debug things
    #XXX:(yuting): if no boothost fond. use js-config.yaml 
    #XXX:(yuting): jump it. TODO here.
    #my $yaml = read_file("/INSTALL/js-config.yaml");
    #my $self = eval { YAML::Load($yaml) };
    #crapout("Unable to load /INSTALL/js-config.yaml") if($@);
    
    my $hostname = $ENV{"hostname"};
    
    open my $cmd, "echo 'GET /jumpstart/hostconfig.cgi?hostname=$hostname' | " .
	"nc boothost 9999|";
    my @out = <$cmd>;
    close $cmd;

    open my $tmpfile,">","/tmp/js.parm.yaml";
    my $ooo=join "\n",@out;
    print $tmpfile $ooo;
    close $tmpfile;

    my $self = eval { YAML::Load(join "\n", @out) };    
    $self->{hostname}=$hostname;

    #XXX:(yuting): set boothost key when new a instance config.
    #XXX:(yuting): if u set another ip /gw /mask need todo..
    my ($ip,$boothost,$gateway,$netmask) = split(/:/,$ENV{ip});
    $self->{boothost} = $boothost;
    $self->{gateway} = $gateway;
    $self->{netmask} = $netmask;
    #XXX:(yuting): todo upstream it to jumpstart.cf .
    $self->{primary_iface} = "eth0";
    
    
    bless $self, $class;
}

sub get {
    my ($self, $setting) = @_;
    
    unless (exists $self->{$setting}) {
        warn "WARN: Unknown setting $setting\n";
        return;
    }
    return $self->{$setting};
}

sub is {
    my ($self, $setting) = @_;
    my $value = $self->get($setting);
    my $retvalue = $value && $value ne "no";
    return $retvalue;
}

sub set {
    my ($self, $setting, $value) = @_;
    $self->{$setting} = $value;
}

1;
