#!/usr/bin/perl
#
use strict;
use warnings 'all';
use DBI;
use Fatal qw/:void open/;
use Seco::AwesomeRange qw/:common/;

my %ip_host;
my %host_aliases;

sub parse_tinydns {
    open my $fh, "/etc/service/tinydns/root/data";
    my $i=0;
    while (<$fh>) {
        print STDERR "\rDEBUG: Parsing tinydns data... ($i)" if $i % 10000 == 0;
        $i++;
        if (/^\+([^:]+):([^:]+):0/) {
            my ($host, $ip) = ($1, $2);
            my $canon_host = $ip_host{$ip};

            if ($canon_host) {
                next if $canon_host eq $host;
                push @{$host_aliases{$canon_host}}, $host;
                for my $alias (@{$host_aliases{$canon_host}}) {
                    push @{$host_aliases{$host}}, $alias;
                }
            } else {
                $ip_host{$ip} = $host;
                push @{$host_aliases{$host}}, $ip;
                push @{$host_aliases{$host}}, $host;
            }
        } elsif (/^C([^:]+):([^:]+)\.:0/) {
            my ($alias, $canon) = ($1, $2);
            push @{$host_aliases{$canon}}, $alias;
        }
    }
    close $fh;

    print STDERR "\rDEBUG: Parsing tinydns data... ($i)  OK\n";
}

sub fully_qualify {
    my $host = shift;
    if ($host =~ /\.[a-z]{2,3}$/i) {
        return $host;
    } else {
        return "$host.inktomisearch.com";
    }
}

my $ofh;
my $cur_prefix = "";

my $sel = "SELECT rsa FROM skh WHERE node=?";
my $dbh = DBI->connect(
    'DBI:Pg:dbname=skh',
    'js',
    'foobar',
    { AutoCommit => 0 }) or die;
my $sel_sth = $dbh->prepare($sel);

sub short_name {
    my $fqdn = shift;
    return unless $fqdn;
    if ($fqdn =~ /\A 
        (.*) # short name
        \.
        (?:
            inktomisearch  |
            (?:
                yst\.corp | # some yahoo domains
                crawl )
                \.yahoo)
            \.com \z/msx) {
        return $1;
    }

    return $fqdn;
}

my %missing_keys;
sub get_all_names {
    my $name = shift;
    if (not exists $host_aliases{$name}) {
        $name =~ s/inktomisearch/inktomi/;
        if (not exists $host_aliases{$name}) {
            return;
        }
    }
    my @aliases = @{$host_aliases{$name}};
    my @short_names = map { short_name($_) } @aliases;
    my @short_yahoo_names = map { s/\.yahoo\.com$//; $_ } @aliases;
    my %names;
    @names{@aliases} = undef;
    @names{@short_names} = undef;
    @names{@short_yahoo_names} = undef;
    return sort keys %names; # uniq
}

sub skh_entry {
    my $canon = shift;
    my $right_prefix = substr($canon, 0, 3);
    if ($right_prefix ne $cur_prefix) {
        close $ofh if $ofh;
        open $ofh, ">>$right_prefix.skh";
    }

    my @all_names = get_all_names($canon);
    return unless @all_names;

    my $aliases = join(",", @all_names);
    $sel_sth->execute(short_name($canon));
    my ($rsa) = $sel_sth->fetchrow_array;
    unless ($rsa) {
        $missing_keys{short_name($canon)}++;
        return;
    }
    for ($rsa) {
        s/^(.*) .*$/$1/; # remove the root@<hostname> part
    }
    print $ofh "$aliases $rsa";
}

my $range = shift;
warn "gen-skh.pl GIVEN $range";
die "Need a range\n" unless $range;
my @nodes = sorted_expand_range($range);
my $num_nodes = @nodes;
die "Need a range\n" unless @nodes;

parse_tinydns();

my $i = 0;

for my $node (@nodes) {
    print STDERR "\rINFO: $i/$num_nodes hosts processed..." if ++$i % 1000 == 0;
    skh_entry(fully_qualify($node));
}

print STDERR "\rINFO: $num_nodes hosts processed                      \n";
if (%missing_keys) {
    print STDERR "MISSING SSH KEYS: " . 
    compress_range(keys %missing_keys) . "\n";
}

END {
    $sel_sth->finish if $sel_sth;
    $dbh->disconnect if $dbh;
}
