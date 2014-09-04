package Seco::OpsDB;

##
#
# $Id: //depot/seco/lib/seco-core/Seco/OpsDB.pm#20 $
#
# An OO Perl interface into the Yahoo! Ops Database
#
##

##
## TODO
## 
## + update docs
## + history/update triggers
## + history helper methods in OpsDB::Node
## + history tables in other DB
## + user groups to limit privs
## + scan helper methods in OpsDB::Node
## + support for ops.contact
## + ops.modelYST
##

use strict;
use warnings;
use Carp;
use Class::DBI::AbstractSearch;
use Class::DBI::Frozen::301;
#use YAML::Syck qw//;
use YAML;
use base qw/Class::DBI/;

# database connection metadata defaults
# can be overridden with db_*() class methods or via .opsdb rcfile
my $RCFILE = '/etc/opsdb.yaml';
my %DB = (
    driver => 'SQL33t', # default is SQLite replica! (we use the eam-hacked
                        # SQL33t with POSIX regex support)
    sqlite => '/home/gemserver/var/opsdb.dat',
    # mySQL specific connection keys
    name   => 'ops',
    host   => undef,
    port   => undef,
    user   => undef,
    passwd => undef,
);

# explicit lists of objects we're allowed to modify and in what ways
use constant OBJ_CREATE => qw/Seco::OpsDB::NodeGroup
                              Seco::OpsDB::NodeGroupMem
			      Seco::OpsDB::Model
			      Seco::OpsDB::MAC/;
use constant OBJ_UPDATE => qw/Seco::OpsDB::Node
                              Seco::OpsDB::NodeGroup
			      Seco::OpsDB::NodeGroupMem
			      Seco::OpsDB::Model
			      Seco::OpsDB::MAC/;
use constant OBJ_DELETE => qw/Seco::OpsDB::NodeGroup
                              Seco::OpsDB::NodeGroupMem
			      Seco::OpsDB::Model
                              Seco::OpsDB::MAC/;

# package globals to store the opsdb account we're using for tracking
# purposes and to serve as a boolean for determining DB writability
my ($OPSDB_ACCOUNT, $ALLOW_NON_PE_UPDATES, @TWIDDLED);

sub rcfile {
    my ($class, $buf) = @_;
    defined($buf) ? $RCFILE = $buf : $RCFILE;
}

sub db_host {
    my ($class, $buf) = @_;
    if (defined($buf)) {
	$DB{host} = $buf;
	push(@TWIDDLED, 'host');
	return;
    }
    
    $DB{host};
}

sub db_name {
    my ($class, $buf) = @_;
    if (defined($buf)) {
	$DB{name} = $buf;
	push(@TWIDDLED, 'name');
	return;
    }

    $DB{name};
}

sub db_port {
    my ($class, $buf) = @_;
    if (defined($buf)) {
	$DB{port} = $buf;
	push(@TWIDDLED, 'port');
	return;
    }
	
    $DB{port};
}

sub db_driver {
    my ($class, $buf) = @_;
    if (defined($buf)) {
	$DB{driver} = $buf;
	push(@TWIDDLED, 'driver');
	return;
    }

    $DB{driver};
}

sub db_sqlite {
    my ($class, $buf) = @_;
    if (defined($buf)) {
	$DB{sqlite} = $buf;
	push(@TWIDDLED, 'sqlite');
	return;
    }

    $DB{sqlite};
}

sub db_user {
    my ($class, $buf) = @_;
    if (defined($buf)) {
	$DB{user} = $buf;
	push(@TWIDDLED, 'user');
	return;
    }

    $DB{user};
}

sub db_passwd {
    my ($class, $buf) = @_;
    push(@TWIDDLED, 'passwd');
    $DB{passwd} = $buf if (defined($buf));
}

sub connect {
    if (-e $RCFILE) {
	#my $config = YAML::Syck::LoadFile($RCFILE);
	my $config = YAML::LoadFile($RCFILE);
	for my $key (keys %DB) {
	    $DB{$key} = $config->{$key}
	      if (exists $config->{$key} and
	          !grep { $_ eq $key } @TWIDDLED);
	}
    }

    if ($DB{driver} eq 'mysql') {
	__PACKAGE__->connection("dbi:$DB{driver}:$DB{name}:$DB{host}:$DB{port}",
				$DB{user}, $DB{passwd},
				{ AutoCommit => 1 });
    }
    elsif (($DB{driver} eq 'SQL33t') or ($DB{driver} eq 'SQLite')) {

	__PACKAGE__->connection("dbi:$DB{driver}:$DB{sqlite}",
				undef, undef,
				{ AutoCommit => 0 });
    
	# if we're running as root, drop privileges before opening
	# the SQLite flat-file to keep it from locking (since we're
	# dealing with it totally read-only anyway)
	if ($> == 0) {
	    my ($new_uid, $new_gid) = (getpwnam('nobody'))[2,3];
	    croak "cannot determine UID/GID for nobody/nogroup"
	      unless (($new_uid) and ($new_gid));
	    $) = $new_gid;
	    $> = $new_uid;
	    __PACKAGE__->db_Main;
	    $> = $<;
	    $) = $(;
	}
    }
    else {
	croak "no support for '$DB{driver}' driver";
    }
}

sub opsdb_account {
    my ($class, $name) = @_;

    # uber-ugly hack to glue together yahoo and inktomi namespaces
    $name = 'jawhn' if (defined $name and $name eq 'jon');

    if ($name) {
	croak "invalid OpsDB account: $name" unless
	  $OPSDB_ACCOUNT = Seco::OpsDB::User->retrieve(username => $name);
    }
    else {
	return (ref($OPSDB_ACCOUNT) eq 'Seco::OpsDB::User') ?
	  $OPSDB_ACCOUNT : undef;
    }
}

sub timestamp {
    my $class = shift;

    my $time;
    if (($DB{driver} eq 'SQL33t') or ($DB{driver} eq 'SQLite')) {
        my $dbh = __PACKAGE__->db_Main;
	my $ent = $dbh->selectcol_arrayref("SELECT * FROM replicametadata");
	croak 'could not determine replica timestamp'
	  unless ((ref($ent)) and ($time = $ent->[0]));
    }
    else {
	$time = time;
    }

    return Time::Piece->strptime($time, '%s');
}

# secret class method that can twiddle the ability to make changes to
# entries that are not associated with 'prod-eng' ownership
sub __allow_non_PE_updates {
    my ($class, $bool) = @_;

    return (defined($bool)) ?
      $ALLOW_NON_PE_UPDATES = $bool :
      $ALLOW_NON_PE_UPDATES;
}

# add a search_regex() method that everyone will inherit
sub search_regex {
    my $self = shift;

    $self->_do_search(REGEXP => @_);
}

sub get_unique {
    my ($class, %args) = (shift, @_);
    return undef unless ($args{field});

    if ($args{where}) {
	map {
	    $args{where}->{$_} = (ref($args{where}->{$_})) ?
	      $args{where}->{$_}->id : $args{where}->{$_}
	} keys %{ $args{where} };
    }

    my $table = $class->table;
    my $query = qq { SELECT DISTINCT $args{field} FROM $table };

    if ($args{where}) {
	$query .= ' WHERE ';
	$query .= join(' AND ', map {
	    "$_ = '$args{where}->{$_}'"
	} keys %{ $args{where} });
    }

    $query .= " ORDER BY $args{field}";

    $class->db_Main->selectcol_arrayref($query);
}

sub __hist_note_changed_cols {
    my ($self, $val, ($col)) = (shift, shift, keys(%{ $_[0] }));

    if (!exists($self->{__ChangedWas}->{$col})) {

	# this refreshes sub-objects if they're not already inflated
	$self->$col if (!exists($self->{$col}));

	$self->{__ChangedWas}->{$col} = (ref($self->{$col})) ?
	  $self->{$col}->name : $self->{$col};
    }

    $self->{__ChangedIs}->{$col} = (ref($val)) ? $val->name : $val;

    return;
};

sub __hist_update {
    my $self = shift;
    return undef unless ($self->{nodeid});

    return undef unless (my @cols = $self->is_changed);

    my $logmsg;
    for my $col (@cols) {
	my $from = $self->{__ChangedWas}->{$col};
	my $to   = $self->{__ChangedIs}->{$col};

	next unless (($from) or ($to));
	next if ((($from) and ($to)) and ($from eq $to));

	if (!$to) {
	    $logmsg .= "[$col] - cleared from \"$from\"\n";
	}
	elsif (!$from) {
	    $logmsg .= "[$col] - set to \"$to\"\n";
	}
	else {
	    $logmsg .= "[$col] - changed from \"$from\" to \"$to\"\n";
	}
    }

    if ($logmsg) {
	chomp($logmsg);

	Seco::OpsDB::History->create({
	    refidx  => bless({ nodeid => $self->{nodeid} },
	                     'Seco::OpsDB::Node'),
	    subject => 'modified',
	    author  => Seco::OpsDB->opsdb_account,
	    history => $logmsg,
	});
    }

    delete($self->{__ChangedWas});
    delete($self->{__ChangedIs});

    return;
}

sub __verify_create {
    my $self = shift;

    my $who = ref($self);
    croak "$who instances are not creatable"
      unless grep { $_ eq $who } OBJ_CREATE;

    $self->__verify_writable;
}

sub __verify_update {
    my $self = shift;

    my $who = ref($self);
    croak "$who instances are not updatable"
      unless grep { $_ eq $who } OBJ_UPDATE;

    $self->__verify_writable;
}

sub __verify_delete {
    my $self = shift;

    my $who = ref($self);
    croak "$who instances are not deletable"
      unless grep { $_ eq $who } OBJ_DELETE;

    $self->__verify_writable;
}

sub __verify_writable {
    my $self = shift;

    croak 'opsdb is read-only when using SQLite'
      if (($DB{driver} eq 'SQL33t') or ($DB{driver} eq 'SQLite'));

    croak 'must set a valid opsdb account before writes are allowed'
      unless (Seco::OpsDB->opsdb_account);

    my $who = ref($self);

    # don't allow any modifications or any references to nodes that
    # are not in group prod-eng or entities not associated with
    # property "yst"
    if ($who eq 'Seco::OpsDB::Node') {
	unless ($self->is_prodeng) {
	    croak "cannot modify $who instances not owned by 'prod-eng'"
	      unless(Seco::OpsDB->__allow_non_PE_updates);
	}
    }
    elsif ($who eq 'Seco::OpsDB::NodeGroup') {
	$self->{prop_id} = Seco::OpsDB::Property->construct($self->{prop_id})
	  unless ref $self->prop_id;
	unless ($self->prop_id->name eq 'yst') {
	    croak "cannot modify $who instances not associated with property 'yst'"
	      unless(Seco::OpsDB->__allow_non_PE_updates);
	}
    }
    elsif ($who eq 'Seco::OpsDB::NodeGroupMem') {
	$self->{node_id} = Seco::OpsDB::Node->construct($self->{node_id})
	  unless ref $self->node_id;
	unless ($self->node_id->is_prodeng) {
	    croak "cannot assign non prod-eng nodes to groups"
	      unless(Seco::OpsDB->__allow_non_PE_updates);
	}
    }
    elsif ($who eq 'Seco::OpsDB::MAC') {
	$self->{node_id} = Seco::OpsDB::Node->construct($self->{node_id})
	  unless ref $self->node_id;
	unless ($self->node_id->is_prodeng) {
	    croak "cannot assign non prod-eng nodes to properties"
	      unless(Seco::OpsDB->__allow_non_PE_updates);
	}
    }

    return;
}

sub __trigger_init {
    my $class = shift;

    # any class that calls __trigger_init() gets the __verify_writable() trigger
    $class->add_trigger(before_create => \&__verify_create);
    $class->add_trigger(before_update => \&__verify_update);
    $class->add_trigger(before_delete => \&__verify_delete);

    # TODO re-enable history
    # for now just bail out and don't deal with history
    return;

    # we only install the triggers for maintaining ycm.history if
    # the calling class advertises a list of columns to keep track of
    return unless $class->can('HIST_COLS');

    for my $col ($class->HIST_COLS) {
	$class->add_trigger("before_set_$col" => \&__hist_note_changed_cols);
    }

    $class->add_trigger(after_update => \&__hist_update);

    return;
}

sub __check_lc {
    my ($val) = @_;
    return $val !~ /[a-z]/;
}

##

package Seco::OpsDB::NodeGroupMem;

use strict;
use base qw/Seco::OpsDB/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('groupNode_node');
__PACKAGE__->columns(All => qw/gn_id node_id/);
__PACKAGE__->columns(Primary => qw/gn_id node_id/);
__PACKAGE__->has_a(gn_id => 'Seco::OpsDB::NodeGroup');
__PACKAGE__->has_a(node_id => 'Seco::OpsDB::Node');

##

package Seco::OpsDB::NodeGroup;

use strict;
use base qw/Seco::OpsDB/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('groupNode');
__PACKAGE__->columns(All => qw/gn_id name description dict_id user_id
                               prop_id parent_id c_time m_time/);
__PACKAGE__->columns(Primary => qw/gn_id/);
__PACKAGE__->columns(Essential => qw/name dict_id user_id prop_id parent_id/);
__PACKAGE__->has_many(nodes => [ 'Seco::OpsDB::NodeGroupMem' => 'node_id' ]);
__PACKAGE__->has_a(user_id => 'Seco::OpsDB::User');
__PACKAGE__->has_a(dict_id => 'Seco::OpsDB::Dictionary');
__PACKAGE__->has_a(prop_id => 'Seco::OpsDB::Property');
__PACKAGE__->has_a(parent_id => 'Seco::OpsDB::NodeGroup');

##

package Seco::OpsDB::Dictionary;

use strict;
use base qw/Seco::OpsDB/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('dictionary');
__PACKAGE__->columns(All => qw/dict_id name description parent_id
                               order_num/);
__PACKAGE__->columns(Primary   => qw/dict_id/);
__PACKAGE__->columns(Essential => qw/name parent_id/);
__PACKAGE__->has_a(parent_id   => 'Seco::OpsDB::Dictionary');

##

package Seco::OpsDB::Company;

use strict;
use base qw/Seco::OpsDB/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('company');
__PACKAGE__->columns(All => qw/company_id name description handle dict_id
                               parent_id/);
__PACKAGE__->columns(Primary   => qw/company_id/);
__PACKAGE__->columns(Essential => qw/name parent_id/);
__PACKAGE__->has_a(dict_id     => 'Seco::OpsDB::Dictionary');
__PACKAGE__->has_a(parent_id   => 'Seco::OpsDB::Company');

##

package Seco::OpsDB::Site;

use strict;
use base qw ( Seco::OpsDB );

__PACKAGE__->__trigger_init;
__PACKAGE__->table('site');
__PACKAGE__->columns(All => qw/site_id name domain is_active
                               address_1 address_2 city state
			       postal country_id company_id
			       snmp_ro snmp_rw description
			       parent_id ownership sitetype timezone
			       c_time m_time/);
__PACKAGE__->columns(Primary   => qw/site_id/);
__PACKAGE__->columns(Essential => qw/name domain parent_id/);
__PACKAGE__->has_a(country_id  => 'Seco::OpsDB::Country');
__PACKAGE__->has_a(company_id  => 'Seco::OpsDB::Company');
__PACKAGE__->has_a(parent_id   => 'Seco::OpsDB::Site');
__PACKAGE__->has_a(c_time  => 'Time::Piece',
                   inflate => sub { Time::Piece->strptime(shift, '%s') },
		   deflate => 'epoch' );
__PACKAGE__->has_a(m_time  => 'Time::Piece',
                   inflate => sub { Time::Piece->strptime(shift, '%Y-%m-%d %H:%M:%S') });

##

package Seco::OpsDB::User;

use strict;
use base qw/Seco::OpsDB/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('user');
__PACKAGE__->columns(All => qw/user_id username employee_id name
			       c_time m_time/);
__PACKAGE__->columns(Primary   => qw/user_id/);
__PACKAGE__->columns(Essential => qw/username/);
__PACKAGE__->has_a(c_time  => 'Time::Piece',
                   inflate => sub { Time::Piece->strptime(shift, '%s') },
		   deflate => 'epoch' );
__PACKAGE__->has_a(m_time  => 'Time::Piece',
                   inflate => sub { Time::Piece->strptime(shift, '%Y-%m-%d %H:%M:%S') });

##

package Seco::OpsDB::Model;

use strict;
use Carp;
use base qw/Seco::OpsDB/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('model');
__PACKAGE__->columns(All => qw/model_id name description company_id
			       max min is_qualified/);
__PACKAGE__->columns(Essential => qw/name company_id/);
__PACKAGE__->columns(Primary   => qw/model_id/);
__PACKAGE__->has_a(company_id  => 'Seco::OpsDB::Company');

# model.min and model.max are poorly named  :(
sub accessor_name {
    my ($class, $col) = @_;
    $col =~ s/^(min|max)$/$1_power/;
    return $col;
}

##

package Seco::OpsDB::Property;

use strict;
use base qw/Seco::OpsDB/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('property');
__PACKAGE__->columns(All => qw/prop_id name description domain
			       country_id is_partner
			       pr_parent_id pa_parent_id
			       fin_cc_cor_num fin_cc_cor_name
			       fin_cc_opex_num fin_cc_opex_name
			       fin_bu_num fin_bu_name fin_is_allocatable
			       c_time m_time
			       is_legacy/);
__PACKAGE__->columns(Essential => qw/name domain/);
__PACKAGE__->columns(Primary => qw/prop_id/);
__PACKAGE__->has_a(country_id => 'Seco::OpsDB::Country');
__PACKAGE__->has_a(pr_parent_id => 'Seco::OpsDB::Property');
__PACKAGE__->has_a(pa_parent_id => 'Seco::OpsDB::Property');
__PACKAGE__->has_a(c_time  => 'Time::Piece',
                   inflat  => sub { Time::Piece->strptime(shift, '%s') },
		   deflate => 'epoch' );
__PACKAGE__->has_a(m_time  => 'Time::Piece',
                   inflate => sub { Time::Piece->strptime(shift, '%Y-%m-%d %H:%M:%S') });

##

package Seco::OpsDB::Country;

use strict;
use base qw/Seco::OpsDB/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('country');
__PACKAGE__->columns(All => qw/country_id code name region/);
__PACKAGE__->columns(Primary => qw/country_id/);

##

package Seco::OpsDB::State;

use strict;
use base qw/Seco::OpsDB/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('state');
__PACKAGE__->columns(All => qw/state_id country_id code name/);
__PACKAGE__->columns(Primary => qw/country_id/);
__PACKAGE__->has_a(country_id => 'Seco::OpsDB::Country');

##

package Seco::OpsDB::MAC;

use strict;
use base qw/Seco::OpsDB/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('mac');
__PACKAGE__->columns(All => qw/node_id mac/);
__PACKAGE__->columns(Primary => qw/node_id mac/);
__PACKAGE__->has_a(node_id => 'Seco::OpsDB::Node');

##

package Seco::OpsDB::OS;

use strict;
use base qw/Seco::OpsDB/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('os');
__PACKAGE__->columns(All => qw/os_id dict_id version parent_id is_deprecated
                               is_gemstone order_num c_time m_time/);
__PACKAGE__->columns(Essential => qw/dict_id version/);
__PACKAGE__->columns(Primary   => qw/os_id/);
__PACKAGE__->has_a(dict_id => 'Seco::OpsDB::Dictionary');
__PACKAGE__->has_a(c_time  => 'Time::Piece',
                   inflat  => sub { Time::Piece->strptime(shift, '%s') },
		   deflate => 'epoch' );
__PACKAGE__->has_a(m_time  => 'Time::Piece',
                   inflate => sub { Time::Piece->strptime(shift, '%Y-%m-%d %H:%M:%S') });

##

package Seco::OpsDB::Node;

use strict;
use Carp;
use base qw/Seco::OpsDB Seco::Node::Purpose/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('node');
__PACKAGE__->columns(All => qw/node_id name ytag type_id status parent_id
                               prop_id site_id backplane model_id os_id
			       serialno locroom loccage locarea locrow
			       locrack locside locshelf racksize bootbox_id
			       bport bmodule bplug bootbox2_id bport2 bmodule2
			       bplug2 console_id cport netswitch_id sport
			       ponumber notes c_time m_time s_time/);
__PACKAGE__->columns(Primary   => qw/node_id/);
__PACKAGE__->columns(Essential => qw/name type_id notes netswitch_id sport
                                     ytag status console_id cport site_id
				     model_id/);
__PACKAGE__->has_many(groups => [ 'Seco::OpsDB::NodeGroupMem' => 'gn_id' ]);
__PACKAGE__->has_many(macs   => 'Seco::OpsDB::MAC');
__PACKAGE__->has_a(prop_id      => 'Seco::OpsDB::Property');
__PACKAGE__->has_a(site_id      => 'Seco::OpsDB::Site');
__PACKAGE__->has_a(os_id        => 'Seco::OpsDB::OS');
__PACKAGE__->has_a(console_id   => 'Seco::OpsDB::Node');
__PACKAGE__->has_a(bootbox_id   => 'Seco::OpsDB::Node');
__PACKAGE__->has_a(bootbox2_id  => 'Seco::OpsDB::Node');
__PACKAGE__->has_a(type_id      => 'Seco::OpsDB::Dictionary');
__PACKAGE__->has_a(netswitch_id => 'Seco::OpsDB::Node');
__PACKAGE__->has_a(model_id     => 'Seco::OpsDB::Model');
__PACKAGE__->has_a(s_time  => 'Time::Piece',
                   inflate => sub { Time::Piece->strptime(shift, '%s') },
		   deflate => 'epoch' );
__PACKAGE__->has_a(c_time  => 'Time::Piece',
                   inflate => sub { Time::Piece->strptime(shift, '%s') },
		   deflate => 'epoch' );
__PACKAGE__->has_a(m_time  => 'Time::Piece',
                   inflate => sub { Time::Piece->strptime(shift, '%Y-%m-%d %H:%M:%S') });
__PACKAGE__->add_constraint('no_lowercase', locarea => \&Seco::OpsDB::__check_lc);

# some backwards-compat methods for the opsdb1 schema
*bornondate  = *c_time;
*site        = *site_id;
*siteid      = *site_id;
*property    = *prop_id;
*type        = *type_id;
*nodetype    = *type_id;
*netswitch   = *netswitch_id;
*console     = *console_id;
*bootbox     = *bootbox_id;
*bootbox2    = *bootbox2_id;
*description = *notes;
*model       = *model_id;

sub mac {
    my ($self, $addr) = (shift, shift);
    my $it = $self->macs;

    if ($addr) {
	if ($it) {
	    while (my $mac = $it->next) {
		$mac->delete;
	    }
	}
	Seco::OpsDB::MAC->create({
	    node_id => $self,
	    mac     => $addr,
	});

	return;
    }
    else {
	return ($it) ? $it->next->mac : undef;
    }
}

# jumpstart shortcut to get all MAC addrs in one query
sub getallmacs {
    my $class = shift;

    my $dbh = __PACKAGE__->db_Main;
    my $sql = qq {
      SELECT
        node.name, mac.mac
      FROM
        node, mac
      WHERE
        node.node_id = mac.node_id
    };

    my $sth = $dbh->prepare($sql);
    $sth->execute;
    my $data;
    while (my $ent = $sth->fetchrow_arrayref) {
	$data->{$ent->[0]} = $ent->[1];
    }
    $sth->finish;

    return $data;
}

# here for legacy API support, don't use this
sub orders {
    my $self = shift;
    return grep { $_->name =~ /^yst-/ } $self->groups;
}

# here for legacy API support, don't use this
sub order {
    my ($self, $order) = @_;

    return $self->legacy_set_group('order', $order) if ($order);

    return undef unless $order = ($self->orders)[0];
    return $order;
}

# here for legacy API support, don't use this
sub projects {
    my $self = shift;
    return grep { $_->name =~ /^ystp-/ } $self->groups;
}

# here for legacy API support, don't use this
sub project {
    my ($self, $project) = @_;

    return $self->legacy_set_group('project', $project) if ($project);

    return undef unless $project = ($self->projects)[0];
    return $project;
}

# here for legacy API support, don't use this
sub legacy_set_group {
    my ($self, $gtype, $obj) = @_;
    my $prefix;

    croak "must be passed Seco::OpsDB::NodeGroup instance"
      unless (ref($obj) eq 'Seco::OpsDB::NodeGroup');

    if ($gtype eq 'order') {
	$prefix = 'yst-';
    }
    elsif ($gtype eq 'project') {
	$prefix = 'ystp-';
    }
    else {
	croak "unknown gtype '$gtype'";
    }

    # first clear any existing node <-> nodesgrp relationships
    my $it = Seco::OpsDB::NodeGroupMem->search_where(node_id =>
                                                     $self->node_id);

    my $regex = qr/$prefix/;
    while (my $ngm = $it->next) {
	$ngm->delete if ($ngm->gn_id->name =~ /^$regex/);
    }

    # ...and create our new relationship
    Seco::OpsDB::NodeGroupMem->create({
	gn_id   => $obj,
	node_id => $self,
    });

    return;
}

# add_group(), del_group(), del_all_groups() are the supported methods for
# tweaking node:group membership
sub add_group {
    my ($self, $obj) = @_;

    croak "must be passed Seco::OpsDB::NodeGroup instance"
      unless (ref($obj) eq 'Seco::OpsDB::NodeGroup');

    Seco::OpsDB::NodeGroupMem->create({
	gn_id   => $obj,
	node_id => $self,
    });

    return;
}

sub del_group {
    my ($self, $obj) = @_;

    croak "must be passed Seco::OpsDB::NodeGroup instance"
      unless (ref($obj) eq 'Seco::OpsDB::NodeGroup');

    my $ngm = Seco::OpsDB::NodeGroupMem->retrieve(node_id => $self->node_id,
                                                  gn_id   => $obj->gn_id);
    return undef unless $ngm;
    $ngm->delete;

    return;
}

sub del_all_groups {
    my $self = shift;
    for ($self->groups) {
	$self->del_group($_) unless $_->name eq 'prod-eng';
    }
    return;
}

sub is_prodeng {
    my $self = shift;
    return (grep { $_->name eq 'prod-eng' } $self->groups) ? 1 : undef;
}

# TODO fixme
sub history {
    return ();
}

sub history_last {
    my $self = shift;
    return ($self->history)[-1];
}

sub history_field {
    my ($self, $field) = @_;

    return undef unless ($field);

    my $it = $self->history;
    my @vals;
    while (my $hist = $it->next) {
	push(@vals, $2) if ($hist->history =~
	  /\[$field\] - (set to|changed from .* to) \"(.*)\"/);
    }

    return (pop @vals) ? \@vals : undef;
}

sub history_last_field {
    my ($self, $field) = @_;
    return ($self->history_field($field))->[-1];
}

# a special, smarter retrieve() method specific for Seco::OpsDB::Node
# that groks a domain search path
# TODO get a defaultdomain from opsdb.yaml
sub smart_retrieve {
    my ($class, %params) = (shift, @_);

    my $name = $params{name};
    my $searchpath = $params{searchpath};
    delete($params{searchpath});

    if (($searchpath) and (ref($searchpath) eq 'ARRAY') and ($name)) {
	for my $domain (@{ $searchpath }) {
	    my $node;
	    $domain =~ s/^\.//;
	    $params{name} = $name . '.' . $domain;

	    # allow matching on just basename if passed "" or "."
            $params{name} = $name if $domain eq "";

	    return $node if $node = $class->retrieve(%params);
	}
    }
    else {
	return $class->retrieve(%params);
    }
    return undef;
}

# this gets scary
sub complex_search {
    my ($class, %args) = (shift, @_);

    $args{fields} = {} if (!$args{fields});

    croak "complex_search(): 'fields' must be passed as a hashref"
      unless(ref($args{fields}) eq 'HASH');

    my $dbh = __PACKAGE__->db_Main;
    my @allcols = map { $_->name } __PACKAGE__->columns;
    my @stdcols = map { $_->name } __PACKAGE__->columns('Essential');

    my $cols;
    if ($args{additional_attrs}) {
	if (ref($args{additional_attrs}) eq 'ARRAY') {
	    $cols = \@stdcols;
	    for my $ent (@{ $args{additional_attrs} }) {
		push(@{ $cols }, $ent) unless
		  ((grep  {$_ eq $ent} @{ $cols }) or
		   (!grep {$_ eq $ent} @allcols));
	    }
	}
	elsif ($args{additional_attrs} =~ /^all$/i) {
	    $cols = \@allcols;
	}
    }
    else {
	$cols = \@stdcols;
    }

    @{ $cols } = map { $_ = 'n.' . $_ } @{ $cols };

    my $sel = join(', ', @{ $cols });
    my $sql = "SELECT $sel FROM node n,";

    # we modify the fields hashref in places, so we copy it
    # just in case it was not passed anonymously
    # yes.  gross and stupid.  and convenient and safe.
    my %fields_copy = %{ $args{fields} };
    $args{fields} = \%fields_copy;

    # alias friendly names to column names for opsdb1 back-compat
    my %col_map = (
        site => 'site_id',
        siteid => 'site_id',
        console => 'console_id',
        netswitch => 'netswitch_id',
        switch => 'netswitch_id',
        bootbox => 'bootbox_id',
        bootbox2 => 'bootbox_id',
        type => 'type_id',
        nodetype => 'type_id',
        property => 'prop_id',
        model => 'model_id',
	description => 'notes',
    );

    # if we were given anything now associated via a nodegroup
    # (owner, order, etc) just collapse into a group list
    my $groups;
    for my $ent (qw/group owner order project/) {
	if (exists $args{fields}->{$ent}) {
	    if (ref $args{fields}->{$ent} eq 'ARRAY') {
		push @{ $groups }, @{ $args{fields}->{$ent} };
	    }
	    else {
		push @{ $groups }, $args{fields}->{$ent};
	    }
	    delete $args{fields}->{$ent};
	}
    }
    $args{fields}->{group} = $groups if $groups;

    # calculate joins and any lookup table relationships
    my ($join, $where);
    for my $col (keys %{$args{fields}}) {
	my $parent_class;
	if ($col eq 'group') {
	    $parent_class = 'Seco::OpsDB::NodeGroup';
	    $join .= ' groupNode_node ngm,';
	}
	elsif (($col eq 'site') or
	       ($col eq 'site_id')) {
	    $parent_class = 'Seco::OpsDB::Site';
	}
	elsif (($col eq 'console') or
	       ($col eq 'console_id')  or
	       ($col eq 'switch')  or
	       ($col eq 'netswitch')  or
	       ($col eq 'netswitch_id')  or
	       ($col eq 'bootbox') or
	       ($col eq 'bootbox_id') or
	       ($col eq 'bootbox2') or
	       ($col eq 'bootbox2_id')) {
	    $parent_class = 'Seco::OpsDB::Node';
	}
	elsif (($col eq 'property') or
	       ($col eq 'prop_id')) {
	    $parent_class = 'Seco::OpsDB::Property';

	    # hack to make property "inktomi" transparently map to "yst"
	    if (ref $args{fields}->{$col} eq 'ARRAY') {
		map {
		    $_ = 'yst' if $_ eq 'inktomi';
		} @{ $args{fields}->{$col} };
	    }
	    else {
		$args{fields}->{$col} = 'yst'
		  if $args{fields}->{$col} eq 'inktomi';
	    }
	}
	elsif ($col eq 'mac') {
	    $join .= ' mac,';
	}
	elsif (($col eq 'type') or
	       ($col eq 'nodetype') or
	       ($col eq 'type_id')) {
	    $parent_class = 'Seco::OpsDB::Dictionary';
	}
	elsif (($col eq 'model') or
	       ($col eq 'model_id')) {
	    $parent_class = 'Seco::OpsDB::Model';
	}

	# if we have a lookup table relationship, pre-fetch that now
	if ($parent_class) {
	    if (ref($args{fields}->{$col}) eq 'ARRAY') {

		# yes, more stupidity
		my @a_copy = @{ $args{fields}->{$col} };
		$args{fields}->{$col} = \@a_copy;

		for (my $i = 0; $i <= $#{ $args{fields}->{$col} }; $i++) {
		    my $search = $args{fields}->{$col}->[$i];
		    next if ($search eq '');
		    $args{fields}->{$col}->[$i] =
		      $parent_class->retrieve(name => $search);
		    croak "no such $col '$search'"
		      unless ($args{fields}->{$col}->[$i]);
		}
		@{ $args{fields}->{$col} } =
		  grep { ref($_) or $_ eq '' } @{ $args{fields}->{$col} };
	    }
	    else {
		my $search = $args{fields}->{$col};
		unless ($search eq '') {
		    my $type = $class->__get_cmp_op($search);
		    if ($type =~ /REGEXP/) {
			$search =~ s#(^/|/$)##g;
			my @ent = $parent_class->search_regex(name => $search);
			croak "nothing matches regex '$search'" unless @ent;
			$args{fields}->{$col} = \@ent;
		    }
		    elsif ($type =~ /LIKE/) {
			my @ent = $parent_class->search_like(name => $search);
			croak "nothing matches '$search'" unless @ent;
			$args{fields}->{$col} = \@ent;
		    }
		    else {
			my @ent = $parent_class->search_where(name => $search);
			croak "no such $col '$search'" unless @ent;
			$args{fields}->{$col} = \@ent;
		    }
		}
	    }
	}

	if (($parent_class) and ($parent_class eq 'Seco::OpsDB::NodeGroup')) {
	    if (ref($args{fields}->{$col}) eq 'ARRAY') {
                $where .= '( ngm.node_id = n.node_id AND ngm.gn_id IN (';
                $where .= join(',',  map { $_->id } @{ $args{fields}->{$col} });
                $where .= ')) AND ';
	    }
	    else {
		my $id = $args{fields}->{$col}->id;
		$where .=
		  "(ngm.node_id = n.node_id AND ngm.gn_id = $id) AND ";
	    }
	}
	elsif ($col eq 'mac') {
	    if (ref($args{fields}->{$col}) eq 'ARRAY') {
		$where .= '( ';
		$where .= join(' OR ', map {
		    'mac.node_id = n.node_id AND upper(mac.mac)' .
		    $class->__get_cmp_op($_) . $dbh->quote(uc($_))
		} @{ $args{fields}->{$col} });
		$where .= ') AND ';
	    }
	    else {
		$where .=
		  'mac.node_id = n.node_id AND upper(mac.mac)' .
		  $class->__get_cmp_op($args{fields}->{$col}) .
		  $dbh->quote(uc($args{fields}->{$col})) . ' AND ';
	    }
	}
	else {
	    my $m_col = exists($col_map{$col}) ?  $col_map{$col} : $col;
	    if (ref($args{fields}->{$col}) eq 'ARRAY') {
		$where .= '( ';
		$where .= join(' OR ', map {
		    my $id = (ref($_)) ? $_->id : $_ ;
		    "n.$m_col" . $class->__get_cmp_op($id) . $dbh->quote($id)
		} @{ $args{fields}->{$col} });
		$where .= ' ) AND ';
	    }
	    else {
		my $id = (ref($args{fields}->{$col})) ?
		  $args{fields}->{$col}->id : $args{fields}->{$col};
		$where .= "n.$m_col" .
		          $class->__get_cmp_op($args{fields}->{$col}) .
		          $dbh->quote($id) . ' AND ';
	    }
	}
    }

    $sql .= $join if ($join);
    $sql =~ s/,$//;
    $sql .= ' WHERE ' . $where if ($where);
    $sql =~ s/OR ([A-Za-z0-9\.]+) (REGEXP|LIKE|=) '&/AND $1 $2 '/g;
    $sql =~ s/(REGEXP|LIKE) '!/NOT $1 '/g;
    $sql =~ s/= '!/!= '/g;
    $sql =~ s/REGEXP '\/(\S+)\/'/REGEXP '$1'/g;
    $sql =~ s/AND $//;

    if ($args{sort}) {
	$args{sort} = [ $args{sort} ] unless (ref($args{sort}) eq 'ARRAY');
	for (@{ $args{sort} }) {
	    $_ = "n.$col_map{$_}" if exists($col_map{$_});
	    $_ = 'ngm1.gid' if (($_ eq 'owner') and
			        ($join) and ($join =~ /ngm1/));
	    $_ = 'ngm2.gid' if (($_ eq 'order') and
			        ($join) and ($join =~ /ngm2/));
	    $_ = 'ngm3.gid' if (($_ eq 'project') and
			        ($join) and ($join =~ /ngm3/));
	    $_ = 'mac.mac'  if (($_ eq 'mac') and
			        ($join) and ($join =~ /mac/));
	}
    }
    else {
	$args{sort} = [ 'n.name' ];
    }

    $sql .= " ORDER BY " . join(',', @{ $args{sort} });

    $sql .= (($args{order}) and ($args{order} =~ /^desc$/i)) ?
      ' DESC ' : ' ASC ';

    my $limit;
    if ((defined($args{numresults})) and ($args{numresults} =~ /^\d+$/)) {
	if ((defined($args{firstresult})) and ($args{firstresult} =~ /^\d+$/)) {
	    $args{firstresult}-- if ($args{firstresult} != 0);
	    $limit = $args{firstresult} . ', ';
	}
	$limit .= $args{numresults}
    }
    $sql .= ' LIMIT ' . $limit if ($limit);

    my $sth = $dbh->prepare($sql);
    my $matches = $sth->execute;

    if ($DB{driver} eq 'mysql') {
	if ($matches =~ /^\d+$/) {
	    my $it = Seco::OpsDB::NodeIterator->new($sth, $matches);
	    return $it;
	}
    }
    # since DBD::SQLite isn't capable of telling us how many rows
    # we selected, we pollute memory a bit by shoving a subset of the
    # return into the Seco::OpsDB::NodeIterator object (similar to how
    # Class::DBI::Iterator behaves by default)
    elsif (($DB{driver} eq 'SQL33t') or ($DB{driver} eq 'SQLite')) {
	if ($matches eq '0E0') {
	    $matches = 0;
	    my $res;
	    while (my $ent = $sth->fetchrow_hashref) {
		push(@{ $res }, $ent);
		$matches++;
	    }
	    $sth->finish;

	    return undef if (!$matches);

	    my $it = Seco::OpsDB::NodeIterator->new($res, $matches);
	    return $it;
	}
    }

    $sth->finish;
    return undef;
}

sub __get_cmp_op {
    my ($class, $string) = @_;

    if ($string =~ /%/) {
	return ' LIKE ';
    }
    elsif ($string =~ /^&?!?\/.*\/$/) {
	croak 'no regular expression support when using SQLite'
	  if ($DB{driver} eq 'SQLite');
	return ' REGEXP ';
    }
    else {
	return ' = ';
    }
}

##

package Seco::OpsDB::NodeIterator;

use strict;
use Carp;

sub new {
    my ($class, $sth, $matches) = @_;

    return bless({ __sth => $sth, __matches => $matches }, $class);
}

sub next {
    my $self = shift;

    return undef unless (ref($self->{__sth}));

    my $node = (ref($self->{__sth}) eq 'DBIx::ContextualFetch::st') ?
      $self->{__sth}->fetchrow_hashref : shift(@{ $self->{__sth} });

    return Seco::OpsDB::Node->construct($node) if ($node);

    $self->end;
    return undef;
}

sub end {
    my $self = shift;

    return undef unless (ref($self->{__sth}));

    $self->{__sth}->finish
      if (ref($self->{__sth}) eq 'DBIx::ContextualFetch::st');
    delete($self->{__sth});
    delete($self->{__matches});
    return 1;
}

sub matches {
    my $self = shift;
    $self->{__matches};
}

##

__END__

=pod

=head1 NAME

Seco::OpsDB - An OO Perl interface into the Yahoo! opsdb

=head1 SYNOPSIS

  use Seco::OpsDB;
  Seco::OpsDB->connect;

  use Seco::OpsDB;
  Seco::OpsDB->rcfile('/path/to/file');
  Seco::OpsDB->connect;

  use Seco::OpsDB;
  Seco::OpsDB->db_driver('mysql');
  Seco::OpsDB->db_user('username');
  Seco::OpsDB->db_passwd('password');
  Seco::OpsDB->connect;

  $node  = Seco::OpsDB::Node->retrieve(name =>
                                       'ks301000.inktomisearch.com');
  $site  = $node->siteid->name;
  $cons  = $node->console->name;
  $cport = $node->cport;
  $order = $node->order->name;

  Seco::OpsDB->opsdb_account('valid_opsdb_username');
  $node->order(Seco::OpsDB::NodesGroup->retrieve(name =>
                                                 'yst-kingkong'));
  $node->update;

  $it = Seco::OpsDB::Node->complex_search(fields => {
                                            order => 'yst-kingkong',
					    model => 'A5' });
  $node = $it->next;
  [...]
  $it->end;

=head1 DESCRIPTION

B<Seco::OpsDB> provides a variety of classes to interface with and relate the
various bits of metadata in OpsDB via the SQL back-end.  It is capable
of functioning either in read/write mode against the MySQL master or
in read-only mode against a SQLite replica.

=head1 CONTAINER CLASS METHODS

The following class methods can be called against the B<Seco::OpsDB> container
class.

=over 4

=item B<connect>

Establish a connection with the OpsDB back-end.  This is the only class
method that I<must> be called for the API to function.  The default is
to attempt a connection to an on-disk SQLite replica,
B</home/gemserver/var/opsdb.dat> unless otherwise specified in the
B<rcfile>.

Additionally, the defaults I<and> what is specified
in the rcfile can be overridden by the B<db_*()> class methods I<prior>
to calling B<connect()> (useful for specifying different connection metadata,
connecting the MySQL master, etc.)

=item B<rcfile>

Get/set the the path to the rcfile.  The values set in this file can be
used to override the defaults of the interface but can still be overridden
by the caller via the B<db_*()> class methods.  Defaults to B</root/.opsdb>

If using this method to override the default rcfile, it I<must> be called
prior to calling B<connect()>.

The following values may be set in the rcfile:

  #
  # a sample /root/.opsdb
  #
  host     boxes.corp.yahoo.com          # default
  name     ycm                           # default 
  port     3306                          # default
  driver   mysql                         # default is 'SQL33t' (hacked SQLite)
  user     ws-ops                        # default is null
  passwd   foo                           # default is null

  #
  # setting this _and_ mysql data would be redundant in real-life
  #
  sqlite   /home/gemserver/var/opsdb.dat # default

=item B<db_driver>

Get/set the DBD driver used (this is also how you specify that you're using
a mySQL instance).  Defaults to I<SQL33t> I<(a hacked SQLite driver)>, set to
I<mysql> if not using an on-disk replica.

=item B<db_host>

Get/set the RDBMS host (MySQL only).  Defaults to I<boxes.corp.yahoo.com>.

=item B<db_port>

Get/set the RDBMS port (MySQL only).  Defaults to I<3306>.

=item B<db_user>

Get/set the RDBMS user (MySQL only).  Defaults to I<ws-ops>.

=item B<db_passwd>

Set the RDBMS password (MySQL only).  There is no default so this I<must>
be called prior to B<connect()> if using the MySQL master I<unless> it has
already been set via the B<rcfile>.

=item B<db_name>

Get/set the database name (MySQL only).  Defaults to I<ycm>.

=item B<db_sqlite>

Get/set the path to the SQLite database used (SQLite only).  Defaults to
I</home/gemserver/var/opsdb.dat>

=item B<opsdb_account>

Set the name of the OpsDB user used for making changes.  This effectively
makes your Seco::OpsDB instance I<writable>, a valid OpsDB user account is
required so the history triggers accurately track any changes made.  Croaks
if passed an invalid OpsDB account.

=item B<timestamp>

Return a B<Time::Piece> object that is the timestamp (version) of the OpsDB
replica being used.  If called when connected to the MySQL master, the object
returned will simply be the current time.

=back

=head1 GENERIC CLASS METHODS

The following class methods can be called against any of the B<Seco::OpsDB::*>
data classes that represent individual tables.

=over 4

=item B<retrieve>

Return a single object of type I<class> given a set of criteria.  Croaks
if the criteria passed matches more than one row.

  $yahoo = Seco::OpsDB::Yahoo->retrieve(name => 'bc');
  $node  = Seco::OpsDB::Node->retrieve(name => 'ks301000.inktomisearch.com');

=item B<retrieve_all>

Return a B<Class::DBI::Iterator> object (if called in scalar context)
that allows access to an object of type I<class> for each row in the table.

  $it = Seco::OpsDB::Property->retrieve_all;
  while ($prop = $it->next) {
      print $prop->name, "\n";
  }

=item B<search_where>

Like B<retrieve_all()> but with criteria like B<retrieve()>.

  $it = Seco::OpsDB::Site->search_where(country => 'USA');
  while ($site = $it->next) {
      print $site->name, "\n";
  }

I<NOTE>: If using any of the B<search_*> methods to search for nodes
of any given criteria, you're better off using the B<complex_search()>
method that is specific to the B<Seco::OpsDB::Node> class.

=item B<search_like>

Like B<search_where> but use the SQL LIKE clause for your criteria.

  $it = Seco::OpsDB::Site->search_where(sitename => 'sc%');
  [...]

=item B<search_regex>

Like B<search_like> but use the SQL REGEXP clause for your criteria.

  $it = Seco::OpsDB::Site->search_regex(sitename => '^sc');
  [...]

=item B<count_all>

Return a count of all rows in the table.  (Like a SELECT COUNT(*) FROM...)

  $total_nodes = Seco::OpsDB::Node->count_all;

=item B<get_unique>

Returns a reference to an array of all distinct rows for a certain field
within the table, optionally based on criteria.

  $all_used_sites = Seco::OpsDB::Node->get_unique(field => 'siteid');
  $all_sc5_racks  = Seco::OpsDB::Node->get_unique(field => 'locrack',
    where => { siteid => Seco::OpsDB::Site->retrieve(name => 'sc5') });

=back

=head1 GENERIC INSTANCE METHODS

The following methods can be called against any B<Seco::OpsDB::*> objects.

=over 4

=item B<update>

Commit changes to the database after making changes to the object in question.
(MySQL only I<and> must be in write mode by calling the
Seco::OpsDB-E<gt>opsdb_account class method first).  This will also trigger
any writes to the history table.  Croaks upon failure.

  $node->model('A6');
  $node->update;

=back

=head1 OVERVIEW OF CLASSES/OBJECTS

The following classes/objects are made available.

=head2 Seco::OpsDB::Node

An B<Seco::OpsDB::Node> object represents any machine, console server, switch,
etc and it's relation with the rest of the B<Seco::OpsDB::*> objects.  It's
attributes (there are accessor/mutator methods for each) are:

[accessors that have a (Class::Name) next to them indicate that the accessor
in question returns an object of that type]

  nodeid
  nodename
  ytag
  description
  status
  siteid (Seco::OpsDB::Site)
  location
  locroom
  loccage
  locarea
  locrow
  locrack
  locside
  locshelf
  netswitch (Seco::OpsDB::Node)
  sport
  bootbox (Seco::OpsDB::Node)
  bport
  bmodule
  bplug
  bootbox2 (Seco::OpsDB::Node)
  bport2
  bmodule2
  bplug2
  osname
  osver
  racksize
  manuf (Seco::OpsDB::uDictString)
  model
  serialno
  console (Seco::OpsDB::Node)
  cport
  cbridge (Seco::OpsDB::Node)
  ospatchlevel
  firmware
  nodetype (Seco::OpsDB::uDictString)
  bornondate
  atime
  ponumber
  lastseen
  backup
  critical
  order    (Seco::OpsDB::NodesGroup)
  project  (Seco::OpsDB::NodesGroup)
  owner    (Seco::OpsDB::NodesGroup)
  property (Seco::OpsDB::Property)

Additionally, the following specific instance methods exist:

=over 4

=item B<interfaces>

Return a B<Class::DBI::Iterator> object (if called in scalar context)
which allows access to each B<Seco::OpsDB::Interface> object associated with
the node in question.

=item B<interface>

Return an B<Seco::OpsDB::Interface> object for a specific interface name
(passed as a scalar) or for 'eth0' if no name is passed.

  $eth0 = $node->interface;
  $eth1 = $node->interface('eth1');

=item B<mac>

Return the MAC address for 'eth0' of the node in question if given no
params.  Also capable of setting the MAC address for eth0 I<or>
accessing/mutating the MAC address for any individual interface.

  $eth0_mac = $node->mac;
  $eth1_mac = $node->mac(ifname => 'eth1');

  $node->mac(addr => $new_eth0_macaddr);
  $node->mac(addr => $new_eth1_macaddr, ifname => 'eth1');

=item B<history>

Return a B<Class::DBI::Iterator> object (if called in scalar context)
which allows access to each B<Seco::OpsDB::History> object associated with
the node in question.

=item B<history_last>

Return the last single B<Seco::OpsDB::History> object entry for the node in
question.

=item B<history_field>

Return a reference to an array of all of the previous values for the specific
I<field> passed for the node in question.

  for (@{ $node->history_field('nodename') }) {
      print "previously named: $_\n";
  }

=item B<history_last_field>

Like B<history_field()> but only return the I<last> value (other than the
current) the specific field.

  $old_name = $node->history_last_field('nodename');

=item B<purpose>

Attempt to determine the node's I<"purpose"> via B<Seco::Node::Purpose> and
return it as a string.

=item B<model_info>

Return a B<Seco::OpsDB::Model> object (if known) associated with this node.

=back

And the following class methods are implemented by B<Seco::OpsDB::Node>:

=over 4

=item B<smart_retrieve>

Like B<retrieve()> but a special implementation specific to B<Seco::OpsDB::Node>
that takes an additional I<searchpath> param (arrayref) specifying a list
of domains to look for the node in.  Returns an B<Seco::OpsDB::Node> object
for the first match. A domain of "" or "." indicates testing the name without
appending any domain.

  $node = Seco::OpsDB::Node->smart_retrieve(
            name => 'pe100.search.scd',
            searchpath => [ 'inktomisearch.com',
	                    'yahoo.com' ]);

=item B<complex_search>

The most flexible way for searching for groups of nodes that match complex
sets of criteria.  Most B<Seco::OpsDB::Node> attributes can be used as search
criteria.  Any attribute can be prefixed with a 'B<!>' which will negate it.
Additionally, any attribute can be passed a reference to an array of items
that will be B<OR>'d together.  Any element prefixed with a 'B<&>' means it will
be B<AND>'d to the previous element in the list instead of B<OR>'d.

Returns a B<Seco::OpsDB::NodeIterator> object (which functions quite
similarly to B<Class::DBI::Iterator>) that allows access to each
B<Seco::OpsDB::Node> object matched.

  $it = Seco::OpsDB::Node->complex_search(
          sort             => [ 'nodename', 'siteid' ],
	  order            => 'asc',
	  numresults       => 100,
	  firstresult      => 1,
	  additional_attrs => ['loccage', 'locrow'],
	  fields => {
	      name     => [ 'ks30100%', '&!/ks30100[5-9]/' ],
	      model    => '/^A[456]$/,
	      manuf    => [ 'Rackable, '' ],
	      property => [ 'yst', 'search' ],
	      order    => 'yst-kingkong',
	      site     => '!re1',
	      [...]
	  });

  print "Number of matches: ", $it->matches;

  while ($node = $it->next) { print $node->name, "\n" }

B<I<NOTE> performance concerns here:>

The B<Seco::OpsDB::Node> objects made available via
B<Seco::OpsDB::NodeIterator> by default will only have a minimal number
of node attributes inflated.  Accessing any non-default attributes will
result in an additional query per object to inflate.  This can be a big
performance hit if selecting a large number of rows.  The optional
B<additional_attrs> param can be passed to B<complex_search()> to alleviate
this.  It can be passed either an arrayref of I<additional>
B<Seco::OpsDB::Node> attr names or simply the string 'all' which will
pre-populate I<all> node attributes.

The list of default attributes populated for a B<Seco::OpsDB::Node> object
are:

  nodename
  nodetype
  cbridge
  netswitch
  sport
  ytag
  status
  console
  cport
  siteid
  model
  description

=item B<getmacbyname>

A light-weight interface into getting the eth0 MAC address for a node
by name in a single query.

  $mac = Seco::OpsDB::Node->getmacbyname($fqdn_nodename);

=item B<getallmacs>

Like B<getmacbyname()> but return a reference to a hash (keyed on nodename)
of all node/macaddr pairs in a single SQL query.

  $allmacs = Seco::OpsDB::Node->getallmacs;

=back

=head2 Seco::OpsDB::History

Objects offer the following accessors:

  histid
  reftable
  refidx
  subject
  author
  timestamp
  history

=head2 Seco::OpsDB::Interface

Objects offer the following accessors:

  intid
  parent_id
  nodeid
  ifName
  ifType
  ifDescr
  ifIndex
  ifMtu
  ifSpeed
  ifPhysAddr
  ifOperStatus
  ifAdminStatus
  ifLastChange
  portDuplex
  paddress
  atime

=head2 Seco::OpsDB::Site

Objects offer the following accessors:

  siteid
  parentid
  sitename
  sitedomain
  address1
  address2
  city
  state
  postal
  country
  ypcontact
  yscontact
  contact
  companyid
  description
  snmpro
  snmprw
  bornondate
  atime

=head2 Seco::OpsDB::Yahoo

Objects offer the following accessors:

  yahooid
  account
  uid
  access
  shell
  md5
  contactid
  sshkeys
  bornondate
  atime

=head2 Seco::OpsDB::Property

Objects offer the following accessors:

  propid
  propname
  paddress
  pcontact
  bornondate
  atime
  propdomain

=head2 Seco::OpsDB::Model

Objects offer the following accesors:

  model_id
  name
  description
  memory
  cpu_num
  cpu_speed
  scsi_disks
  ide_disks
  ipmi
  hw_raid_manuf (Secoo::OpsDB::uDictString)
  hw_raid_model
  phantom
  is_64bit

=head2 Seco::OpsDB::PropNodes

Used for linking nodes E<lt>=E<gt> properties.

=head2 Seco::OpsDB::NodesGroup

Definitions for arbitrary groupings (used for orders among other things).

=head2 Seco::OpsDB::NodesGroupMembers

Massive lookup table for associating nodes E<lt>=E<gt> node groups.

=head2 Seco::OpsDB::Dictionary

=head2 Seco::OpsDB::uDictString

=head2 Seco::OpsDB::NodeIterator

=head1 EXAMPLES

=head2 Connecting to the MySQL master instead of an on-disk SQLite replica (can
also be done globally via the rcfile)

  use Seco::OpsDB;
  Seco::OpsDB->db_driver('mysql');
  Seco::OpsDB->db_user($mysql_user);
  Seco::OpsDB->db_passwd($mysql_passwd);
  Seco::OpsDB->connect;

=head2 Displaying console info for all B-type nodes from order yst-kingkong in RE3

  $it = Seco::OpsDB::Node->complex_search(fields => {
                                            order => 'yst-kingkong',
                                            site  => 'RE3',
					    model => 'B%' });
  die "no matches" unless ($it);

  print "number of matches: ", $it->matches;

  while ($node = $it->next) {
    printf "node: %s, console: %s, port: %d\n",
	   $node->name, $node->console->name, $node->cport;
  }

=head2 Moving a node to SCI

  Seco::OpsDB->opsdb_account('username'); # makes your instance writable

  $node = Seco::OpsDB::Node->[...];

  $site = Seco::OpsDB::Site->retrieve(name => 'sci');

  $node->siteid($site);
  $node->update;

=head1 AUTHOR

Bruno Connelly, E<lt>F<bc@yahoo-inc.com>E<gt>

=head1 SEE ALSO

Class::DBI(3), Time::Piece(3)

=cut
