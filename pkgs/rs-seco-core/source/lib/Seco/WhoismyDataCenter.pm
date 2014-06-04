package Seco::WhoismyDataCenter;

use Exporter;
use Carp;
use Exporter;

our(@EXPORT, %EXPORT_TAGS, $VERSION);

$VERSION = '1.1.0';
@ISA = qw/Exporter/;
@EXPORT_OK = qw/whoismydatacenter/;
%EXPORT_TAGS = (all => [@EXPORT_OK], common => [@EXPORT_OK]);
@EXPORT = (); # don't pollute the namespace - use Range qw/:common/

# not re-inventing these particular wheels
use strict;
use Seco::Range qw(:common);

sub whoismydatacenter {
  my($target) = @_;
  my($dc) = expand_range("dc($target)");
  $dc = "UNKNOWN" unless (length($dc));
  return $dc;
}

1;
