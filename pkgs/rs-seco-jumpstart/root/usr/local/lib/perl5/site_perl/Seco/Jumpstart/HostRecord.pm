package Seco::Jumpstart::HostRecord;

use 5.006;
use strict;
use warnings 'all';

use Carp;
use YAML;
use Switch;
use Seco::Jumpstart::DB;

use base qw(Seco::Jumpstart::BaseCfg);
use fields qw(node macaddr ip cpus disks idedisks
  softwareraid hwraid hyperthreading ipmi_enabled memory
  def_fs label admin dirty_ modified_);

our $AUTOLOAD;

my $dbh;
my $prepared_select;
my $prepared_insert;
my $prepared_update;
my %host_records;
my @fields;         # fields that will be written to the database
my @fields_node;    # same, but excluding 'node' which is our key

sub new {
    confess "Don't call new on HostRecord, use the get method.";
}

sub get {
    my ($class, $node) = @_;

    my __PACKAGE__ $self = fields::new($class);
    $self->SUPER::new;

    unless (defined $dbh) {
        @fields      = $self->get_fields;
        @fields_node = @fields[ 1 .. $#fields ];
        $dbh         = Seco::Jumpstart::DB->get_dbh;
        $self->create_my_table;
    }

    if (defined $node) {
        return $host_records{$node} if exists $host_records{$node};
        $self->{node} = $node;
        $self->load;
        $host_records{$node} = $self;
    }
    return $self;
}

sub dump_info {
    my __PACKAGE__ $self = shift;
    my @values           = @$self{@fields};
    my $node             = shift @values;
    print "$node\n\t";
    for (my $i = 0 ; $i < @fields_node ; $i++) {
        defined $values[$i] or $values[$i] = "UNDEF";
        print "$fields_node[$i]=$values[$i] ";
        if ($i % 3 == 2) { print "\n\t" }
    }
    print "\n";
}

sub nextboot_name {
    my __PACKAGE__ $self = shift;
    my ($type)           = @_;
    my $label            = $self->{label};
    defined($label) or $label = 'NO-GRUOP';
    my $nextboot = "$label-";

    switch ($type) {
        case "normal" {
            $nextboot .= "N";
        }
        case /install|burnin|guessinstall/ {
            $nextboot .= "I";
        }
        case "emergency" {
            $nextboot .= "E";
        }
        else { $nextboot = $type; }
    };

    return $nextboot;
}

sub _get_hostrecord {
    my __PACKAGE__ $self = shift;
    my ($mode)           = @_;
    my $nextboot         = $self->nextboot_name($mode);
    my ($force, $rootonly, $burnin, $guessinstall) = (0, 0, 0, 0);

    switch ($mode) {
        case "force-install" {
            $force = 1;
        }
        case "root-install" {
            $rootonly = 1;
        }
        case "burnin" {
            $force  = 1;
            $burnin = 1;
        }
        case "force-guessinstall" {
            $force        = 1;
            $guessinstall = 1;
        }
        case "guessinstall" {
            $guessinstall = 1;
        }
    };

    my $hash_ref = {
        profile        => $self->{label},
        macaddr        => $self->{macaddr},
        nextboot       => $nextboot,
        ip             => $self->{ip},
        force          => $force,
        rootonly       => $rootonly,
        idedisks       => $self->{idedisks},
        cpus           => $self->{cpus},
        hyperthreading => $self->{hyperthreading},
        ipmi_enabled   => $self->{ipmi_enabled},
        memory         => $self->{memory},
        disks          => $self->{disks},
        softwareraid   => $self->{softwareraid},
        hwraid         => $self->{hwraid},
        def_fs         => $self->{def_fs},
        burnin         => $burnin,
        guessinstall   => $guessinstall,
    };
    return $hash_ref;
}

sub yaml_hostrecord {
    my __PACKAGE__ $self = shift;
    my $mode = shift || 'normal';
    Dump($self->_get_hostrecord($mode));
}

sub dump_hostrecord {
    my __PACKAGE__ $self = shift;
    my $mode = shift || 'normal';
    my $href = $self->_get_hostrecord($mode);
    for my $setting (sort keys %$href) {
        print "$setting $href->{$setting}\n";
    }
}

sub load {
    my __PACKAGE__ $self = shift;
    my $node = $self->{node};
    confess "load called but node is not set" unless $node;

    my $fields = join(",", @fields);

    $prepared_select ||=
      $dbh->prepare("select $fields from HostRecords where node=?");

    $prepared_select->execute($node) or do {
        $self->log("error", "$node: " . $dbh->errstr);
        return;
    };

    my $all = $prepared_select->fetchall_arrayref();
    if (@$all) {
        @$self{@fields} = @{ $all->[0] };
    }
    else {
        $prepared_insert ||=
          $dbh->prepare("insert into HostRecords (node) values (?)");
        $prepared_insert->execute($node);
    }
}

sub save {
    my __PACKAGE__ $self = shift;
    return unless $self->{dirty_};
    my $node = $self->{node};

    my @values = @$self{@fields_node};

    unless ($prepared_update) {
        my $update = join(",", map { "$_=?" } @fields_node);
        $prepared_update =
          $dbh->prepare("update HostRecords set $update where node = ?");
        $self->{dirty_} = 0;
    }

    $prepared_update->execute(@values, $node);
}

sub get_fields {
    my __PACKAGE__ $self = shift;
    my @result = grep { !/(_$|node)/ } sort keys %$self;
    return ('node', @result);
}

sub create_my_table {
    my __PACKAGE__ $self = shift;

    eval {
        local $dbh->{PrintError} = 0;

        #$dbh->do("DROP TABLE HostRecords");
        my $fields = join(",", @fields_node);
        my $cmd = "CREATE TABLE HostRecords ( node PRIMARY KEY, $fields )";

        $self->log("debug", $cmd);

        $dbh->do($cmd);
    };
}

sub commit {
    $dbh->commit;
}

sub AUTOLOAD {
    my __PACKAGE__ $self = shift;
    my $name = $AUTOLOAD;
    $name =~ s/.*:://;
    return if $name =~ /DESTROY/;

    die "ERROR: $name is not a valid HostRecord field"
      unless exists $Seco::Jumpstart::HostRecord::FIELDS{$name};

    no strict 'refs';
    *{"Seco::Jumpstart::HostRecord::$name"} = sub {
        my __PACKAGE__ $self = shift;
        my $value = $self->{$name};

        if (@_) {
            my $new_value = shift;
            if (not(defined($new_value) and defined($value))
                or $value ne $new_value)
            {
                my $node = $self->{node};
                defined($value) or $value = "UNDEF";

              #print "dirty and modified flags on $node ($new_value, $value)\n";
                $self->{modified_} = 1;
                $self->{dirty_}    = 1;

                # The pseudo hash will complain if the field doesn't exist
                $self->{$name} = $new_value;
            }
        }
        return $self->{$name};
    };

    $self->$name(@_);
}

1;
