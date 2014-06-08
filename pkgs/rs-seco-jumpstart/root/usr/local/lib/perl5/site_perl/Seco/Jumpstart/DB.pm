# bugs: this interface seriously sucks
package Seco::Jumpstart::DB;

use strict;
use warnings;
no warnings 'deprecated';

use constant DB_BACKEND     => "/usr/local/jumpstart/var/jumpstart.sqlite.dat";

use DBI;

use base 'Seco::Jumpstart::BaseCfg';
use fields qw/dbh/;

my DB $instance;
our $filename;

sub get_instance {
    my ($class) = @_;
    return $instance if $instance;

    $instance = fields::new($class);
    $instance->SUPER::new;

    $filename ||= DB_BACKEND;
    die "ERROR: $filename doesn't exist!"
	unless -r $filename;

    $instance->{dbh} =
      DBI->connect("dbi:SQL33t:$filename", "", "",
        { RaiseError => 1, AutoCommit => 0 });

    return $instance;
}

sub get_dbh {
    my $class = shift;
    my $db    = $class->get_instance();
    return $db->{dbh};
}

sub set_dbfilename {
    my ($class, $new_filename) = @_;
    $filename = $new_filename;
}

sub get_dbfilename {
    return $filename ? $filename : DB_BACKEND;
}

1;
