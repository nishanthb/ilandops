package Seco::YRT3::Lite;

##
#
# $Id: //depot/metapkg-ng-packages/seco-core/root/usr/local/lib/perl5/site_perl/Seco/YRT3/Lite.pm#13 $
#
# Perl interface into a light-weight SQLite replica of active Siebel tickets
# (named Seco::YRT3::Lite for legacy reasons)
#
##

use strict;
use warnings;
use Carp;
use Class::DBI::AbstractSearch;
use Class::DBI::Frozen::301;
use Time::Piece;
use base qw /Class::DBI/;

use constant {
    DB_DRIVER => 'SQL33t',
    DB_FILE   => '/home/gemserver/var/siebel.dat',
};

__PACKAGE__->connection('dbi:' . DB_DRIVER . ':' . DB_FILE);

# if running as root, drop privs, force a connection to the database
# and restore privs (get around SQLite write-locking fun)
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

sub timestamp {
    my $class = shift;
    my $dbh = __PACKAGE__->db_Main;
    my $ent = $dbh->selectcol_arrayref("SELECT * FROM replicametadata");
    croak 'could not determine replica timestamp'
      unless ((ref($ent)) and (my $time = $ent->[0]));

    return Time::Piece->strptime($time, '%s');
}

sub search_regex {
    my $self = shift;
    $self->_do_search(REGEXP => @_);
}

sub __trigger_init {
    my $class = shift;
    foreach my $type (qw /create update delete/) {
	$class->add_trigger("before_$type" =>
	  sub { croak "$class instances not writable!" });
    }
}

##

package Seco::YRT3::Lite::User;

use strict;
use base qw /Seco::YRT3::Lite/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('users');
__PACKAGE__->columns(All => qw /id name/);
__PACKAGE__->columns(Essential => qw /id name/);
__PACKAGE__->columns(Primary => qw /id/);

##

package Seco::YRT3::Lite::Queue;

use strict;
use base qw/Seco::YRT3::Lite/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('queues');
__PACKAGE__->columns(All => qw /id name/);
__PACKAGE__->columns(Essential => qw /id name/);
__PACKAGE__->columns(Primary => qw /id/);

##

package Seco::YRT3::Lite::Priority;

use strict;
use base qw/Seco::YRT3::Lite/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('priorities');
__PACKAGE__->columns(All => qw /id name/);
__PACKAGE__->columns(Essential => qw /id name/);
__PACKAGE__->columns(Primary => qw /id/);

##

package Seco::YRT3::Lite::Property;

use strict;
use base qw/Seco::YRT3::Lite/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('properties');
__PACKAGE__->columns(All => qw /id name/);
__PACKAGE__->columns(Essential => qw /id name/);
__PACKAGE__->columns(Primary => qw /id/);

##

package Seco::YRT3::Lite::Location;

use strict;
use base qw/Seco::YRT3::Lite/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('locations');
__PACKAGE__->columns(All => qw /id name/);
__PACKAGE__->columns(Essential => qw /id name/);
__PACKAGE__->columns(Primary => qw /id/);

##

package Seco::YRT3::Lite::Ticket;

use strict;
use Carp;
use base qw/Seco::YRT3::Lite/;

__PACKAGE__->__trigger_init;
__PACKAGE__->table('tickets');
__PACKAGE__->columns(All => qw /id internal_id queue owner subject priority
                                status resolved lastupdatedby lastupdated
				creator created location property/);
__PACKAGE__->columns(Essential => qw /id queue owner subject priority status
                                      resolved lastupdated creator created
				      location property/);
__PACKAGE__->columns(Primary => qw /id/);
__PACKAGE__->has_a(queue         => 'Seco::YRT3::Lite::Queue');
__PACKAGE__->has_a(owner         => 'Seco::YRT3::Lite::User');
__PACKAGE__->has_a(lastupdatedby => 'Seco::YRT3::Lite::User');
__PACKAGE__->has_a(creator       => 'Seco::YRT3::Lite::User');
__PACKAGE__->has_a(priority      => 'Seco::YRT3::Lite::Priority');
__PACKAGE__->has_a(location      => 'Seco::YRT3::Lite::Location');
__PACKAGE__->has_a(property      => 'Seco::YRT3::Lite::Property');
__PACKAGE__->has_a(resolved      => 'Time::Piece',
                   inflate       => sub { Time::Piece->strptime(shift, '%s') },
	           deflate       => 'epoch' );
__PACKAGE__->has_a(lastupdated   => 'Time::Piece',
                   inflate       => sub { Time::Piece->strptime(shift, '%s') },
	           deflate       => 'epoch' );
__PACKAGE__->has_a(created       => 'Time::Piece',
                   inflate       => sub { Time::Piece->strptime(shift, '%s') },
	           deflate       => 'epoch' );

sub url {
    "https://ticketing.corp.yahoo.com/erm_enu/view/" . shift->internal_id;
}

sub url2 {
    "http://ynoc.yahoo.com/cgi-bin/siebel-ticket.cgi?ticket=" . shift->id;
}

sub complex_search {
    my ($class, %args) = (shift, @_);

    croak "complex_search(): 'fields' must be passed as a hashref"
      unless(($args{fields}) and (ref($args{fields}) eq 'HASH'));

    my %fields = %{ $args{fields} };
    my $dbh = __PACKAGE__->db_Main;
    my $sel = join(', ', __PACKAGE__->columns('Essential'));
    my $sql = "SELECT $sel FROM tickets WHERE ";

    foreach my $col (keys %fields) {
	my $parent_class;
	if ($col eq 'queue') {
	    $parent_class = 'Seco::YRT3::Lite::Queue';
	}
	elsif (($col eq 'owner') or
	       ($col eq 'creator') or
	       ($col eq 'lastupdatedby')) {
	    $parent_class = 'Seco::YRT3::Lite::User';
	}
	elsif ($col eq 'priority') {
	    $parent_class = 'Seco::YRT3::Lite::Priority';
	}
	elsif ($col eq 'location') {
	    $parent_class = 'Seco::YRT3::Lite::Location';
	}
	elsif ($col eq 'property') {
	    $parent_class = 'Seco::YRT3::Lite::Property';
	}

	if ($parent_class) {
	    if (ref($fields{$col}) eq 'ARRAY') {
		for (my $i = 0; $i <= $#{ $fields{$col} }; $i++) {
		    my $search = $fields{$col}->[$i];
		    next if $search eq '';
		    $fields{$col}->[$i] =
		      $parent_class->retrieve(name => $search);
		    croak "no such $col '$search'" unless ($fields{$col}->[$i]);
		}
	    }
	    else {
		my $search = $fields{$col};
		unless ($search eq '') {
		    $fields{$col} = $parent_class->retrieve(name => $search);
		    croak "no such $col '$search'" unless ($fields{$col});
		}
	    }
	}

	if (ref($fields{$col}) eq 'ARRAY') {
	    $sql .= '( ';
	    $sql .= join(' OR ', map {
	      $col . $class->__get_cmp_op($_) . $dbh->quote($_)
	    } @{ $fields{$col} });
	    $sql .= ' ) AND ';
	}
	else {
	    $sql .= $col . $class->__get_cmp_op($fields{$col}) .
	            $dbh->quote($fields{$col}) . ' AND ';
	}
    }

    $sql =~ s/,$//;
    $sql =~ s/OR ([A-Za-z0-9\.]+) (REGEXP|LIKE|=) '&/AND $1 $2 '/g;
    $sql =~ s/(REGEXP|LIKE) '!/NOT $1 '/g;
    $sql =~ s/= '!/!= '/g;
    $sql =~ s/REGEXP '\/(\S+)\/'/REGEXP '$1'/g;
    $sql =~ s/AND $//;

    if ($args{sort}) {
	$args{sort} = [ $args{sort} ] unless (ref($args{sort}) eq 'ARRAY');
    }
    else {
	$args{sort} = [ 'id' ];
    }

    $sql =~ s/ WHERE $//;
    $sql .= ' ORDER BY ' . join(',', @{ $args{sort} });

    $sql .= (($args{order}) and ($args{order} =~ /^desc$/i)) ?
      ' DESC ' : ' ASC ';

    my $limit;
    if ((defined($args{numresults})) and ($args{numresults} =~ /^\d+$/)) {
	if ((defined($args{firstresult})) and ($args{firstresult} =~ /^\d+$/)) {
	    $args{firstresult}-- if ($args{firstresult} != 0);
	    $limit = $args{firstresult} . ', ';
	}
	$limit .= $args{numresults};
    }

    $sql .= ' LIMIT ' . $limit if ($limit);

    my $sth = $dbh->prepare($sql);
    my $matches = $sth->execute;

    if ($matches eq '0E0') {
	$matches = 0;
	my $res;
	while (my $ent = $sth->fetchrow_hashref) {
	    push(@{ $res }, $ent);
	    $matches++;
	}
	$sth->finish;

	return undef if (!$matches);

	my $it = Seco::YRT3::Lite::TicketIterator->new($res, $matches);
	return $it;
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
	return ' REGEXP ';
    }
    else {
	return ' = ';
    }
}

##

package Seco::YRT3::Lite::TicketIterator;

use strict;
use Carp;

sub new {
    my ($class, $res, $matches) = @_;
    return bless({ __res => $res, __matches => $matches }, $class);
}

sub next {
    my $self = shift;

    return undef unless (ref($self->{__res}));

    my $ticket = shift(@{ $self->{__res} });

    return Seco::YRT3::Lite::Ticket->construct($ticket) if ($ticket);

    $self->end;
    return undef;
}

sub end {
    my $self = shift;

    return undef unless (ref($self->{__res}));

    delete($self->{__res});
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

Seco::YRT3::Lite - An OO Perl interface into a trimmed down Siebel replica

=head1 SYNOPSIS

  use Seco::YRT3::Lite;

  $ticket_attrs = Seco::YRT3::Lite::Ticket->columns('All');

  $ticket  = Seco::YRT3::Lite::Ticket->retrieve(id => 123456);
  $queue   = $ticket->queue->name;
  $owner   = $ticket->owner->name;
  $creator = $ticket->creator->name;
  $mtime   = $ticket->lastupdated->epoch;
  $mtime_t = $ticket->lastupdated->cdate;

  $it = Seco::YRT3::Lite::Ticket->complex_search(fields => {
	  location => [ 'sc5', 'sk1' ],
	  subject  => '/[fmk]s[0-9]/',
	  status   => [ 'new', 'open', 'stalled', 'rejected' ],
  });

  $ticket = $it->next;
  [...]
  $ticket->end;

=head1 DESCRIPTION

B<Seco::YRT3::Lite> provides an interface into a trimmed-down version
of the Siebel schema that offers OO access to all currently open/new/stalled
tickets in the various ops queues (SA, Site Ops, Fix In Place, Network) as
well as all closed tickets that have been updated within the last month.
Given this operates against a B<replica> of the Siebel instance, this is a
I<read-only> interface.

=head1 CONTAINER CLASS METHODS

The following class methods can be called against the B<Seco::YRT3::Lite>
container class.

=over 4

=item B<timestamp>

Return a B<Time::Piece> object that is the timestamp (version) of when
the data was gathered from the master Siebel instance.

=back

=head1 GENERIC CLASS METHODS

The following class methods can be called against any of the
B<Seco::YRT3::Lite::*> data classes that represent individual tables.

=over 4

=item B<retrieve>

Return a single object of type I<class> given a set of criteria.  Croaks
if the criteria passed matches more than one row.

  $location = Seco::YRT3::Lite::Location->retrieve(name => 'sk1');
  $queue    = Seco::YRT3::Lite::Queue->retrieve(name => 'Site Ops');

=item B<retrieve_all>

Return a B<Class::DBI::Iterator> object (if called in scalar context)
that allows access to an object of type I<class> for each row in the table.

  $it = Seco::YRT3::Lite::Property->retrieve_all;
  while ($prop = $it->next) {
      print $prop->name, "\n";
  }

=item B<search_where>

Like B<retrieve_all()> but with criteria like B<retrieve()>.

  $it = Seco::YRT3::Lite::Ticket->search_where(status => 'stalled');
  while ($ticket = $it->next) {
      print $ticket->subject, "\n";
  }

I<NOTE>: If using any of the B<search_*> methods to search for tickets
of any given criteria, you're better off using the B<complex_search()>
method that is specific to the B<Seco::YRT3::Lite::Ticket> class.

=item B<search_like>

Like B<search_where> but use the SQL LIKE clause for your criteria.

  $it = Seco::YRT3::Lite::Location->search_like(name => 'sc%');
  [...]

=item B<search_regex>

Like B<search_like> but use the SQL REGEXP clause for your criteria.

  $it = Seco::YRT3::Lite::Location->search_regex(name => '^sc');
  [...]

=item B<count_all>

Return a count of all rows in the table.  (Like a SELECT COUNT(*) FROM...)

  $total_tickets_in_replica = Seco::YRT3::Lite::Ticket->count_all;

=back

=head1 OVERVIEW OF CLASSES/OBJECTS

The following classes/objects are made available.

=head2 Seco::YRT3::Lite::Ticket

Accessors:

[accessors that have a (Class::Name) next to them indicate that the accessor
in question returns an object of that type]

  id
  internal_id
  queue (Seco::YRT3::Lite::Queue)
  owner (Seco::YRT3::Lite::User)
  subject
  priority
  status
  resolved (Time::Piece)
  lastupdatedby (Seco::YRT3::Lite::User)
  lastupdated (Time::Piece)
  creator (Seco::YRT3::Lite::User)
  created (Time::Piece)
  location (Seco::YRT3::Lite::Location)
  property (Seco::YRT3::Lite::Property)

And the following class methods are implemented by B<Seco::YRT3::Lite::Ticket>:

=over 4

=item B<url>

Return a URL to retrieve the ticket via the official web interface.

  $webapp_url = $ticket->url;
 
=item B<url2>

Return a URL to retrieve the ticket via the YNOC web interface.

  $ynoc_url = $ticket->url2;

=item B<complex_search>

The most flexible way for searching for groups of tickets that match complex
sets of criteria.  Most B<Seco::YRT3::Lite::Ticket> attributes can be used as
search criteria.  Any attribute can be prefixed with a 'B<!>' which will negate
it.  Additionally, any attribute can be passed a reference to an array of items
that will be B<OR>'d together.  Any element prefixed with a 'B<&>' means it will
be B<AND>'d to the previous element in the list instead of B<OR>'d.

Returns a B<Seco::YRT3::Lite::TicketIterator> object (which functions quite
similarly to B<Class::DBI::Iterator>) that allows access to each
B<Seco::YRT3::Lite::Ticket> object matched.

  $it = Seco::YRT3::Lite::Ticket->complex_search(
          sort             => [ 'created', 'subject' ],
	  order            => 'asc',
	  numresults       => 100,
	  firstresult      => 1,
	  fields => {
	      subject  => [ 'ks30100%', '&!/ks30100[5-9]/' ],
	      status   => 'resolved',
	      queue    => [ 'Site Ops', 'Fix In Place' ],
	      property => 'inktomi',
	      location => '!re1',
	      [...]
	  });

  print "Number of matches: ", $it->matches;

  while ($node = $it->next) { print $ticket->subject, "\n" }

=back

=head2 Seco::YRT3::Lite::User

Objects offer the following accessors:

  id
  name

=head2 Seco::YRT3::Lite::Queue

Objects offer the following accessors:

  id
  name

=head2 Seco::YRT3::Lite::Priority

Objects offer the following accessors:

  id
  name

=head2 Seco::YRT3::Lite::Property

Objects offer the following accessors:

  id
  name

=head2 Seco::YRT3::Lite::Location

Objects offer the following accessors:

  id
  name

=head2 Seco::YRT3::Lite::TicketIterator

=head1 EXAMPLES

=head1 AUTHOR

Bruno Connelly, E<lt>F<bc@yahoo-inc.com>E<gt>

=head1 SEE ALSO

Class::DBI(3), Time::Piece(3)

=cut
