package Seco::Node::Purpose;

##
#
# $Id: //depot/seco/lib/seco-core/Seco/Node/Purpose.pm#6 $
#
# A hardcoded hash of node prefixes, retun type based on prefix regex
# Yes, this is dumb.  However, it serves the purpose for now.
#
##

use strict;
use base qw (Exporter);
use Carp;
use Seco::Range qw (expand_range);

our(@EXPORT_OK, %EXPORT_TAGS, $VERSION);

$VERSION = '1.0.0';
@EXPORT_OK = qw ( node_purpose range_purpose );
%EXPORT_TAGS = ( all => [@EXPORT_OK] );

my @ADMIN = expand_range('@ADMIN');
my %PURPOSE_MAP = (
    '^ats[0-9]'     => 'acceptance_test_storage',
    '^ct5'          => 'catalog_main',
);

sub new {
    my ($class, %args) = (shift, @_);
    my $self = {};
    map { $self->{$_} = $args{$_} } keys %args;
    bless($self, $class);
}

sub purpose {
    my $self = shift;
    return unless ($self->{name});
    node_purpose($self->{name});
}

sub node_purpose {
    my $name = shift;
    return undef unless ($name);

    $name =~ s/\.(inktomisearch|yahoo)\.com$//;

    return 'admin' if grep { $_ eq $name } @ADMIN;

    foreach my $key (sort keys %PURPOSE_MAP) {
	my $regex = qr/$key/;
	return $PURPOSE_MAP{$key} if $name =~ $regex;
    }

    return 'UNKNOWN';
}

sub range_purpose {
    my $range = shift;

    my %purposes;
    croak unless my @nodes = expand_range($range);
    for (@nodes) {
	if (my $purpose = node_purpose($_)) {
	    $purposes{$purpose}++;
	}
    }
    return keys(%purposes) ? keys %purposes : undef;
}

__END__

=pod

=head1 NAME

Seco::Node::Purpose - A stupid interface for guessing a node's purpose

  use Seco::Node::Purpose qw / :all /;
  $purpose = node_purpose('pe1000.search.scd.yahoo.com');
  @purposes = range_purpose('%ks301,%fs301');

  use Seco::Node::Purpose;
  $purpose = Seco::Node::Purpose->new(name => 'ks301000')->purpose;

=head1 BUGS

This implementation is stupid!  :-)

=cut
