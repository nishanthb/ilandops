#!/usr/bin/perl -w
use strict;
use Getopt::Long;
use Pod::Usage;
use constant 'SKH_DIR' => '/usr/local/jumpstart/skh/';
use Seco::AwesomeRange qw/expand_range/;

my $man = 0;
my $help = 0;
my $range;

GetOptions('help|?' => \$help,
	   man      => \$man,
	   'range=s' => \$range
) or pod2usage(2);

pod2usage(1) if $help or not $range;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

my %keys;
open SKH, "/etc/ssh/ssh_known_hosts" or die "skh: $!";
while (<SKH>) {
    my @fields = split;
    next unless $fields[1] =~ /^\d+$/;
    my $name;
    if ($fields[0] =~ /,([-\w.]+)\.inktomi/) {
        $name = $1;
    } else {
        $name = $fields[0];
    }
    if (exists $keys{$name}) {
        print "WARN: $name: Duplicate entries in /etc/ssh/ssh_known_hosts\n";
    } else {
        $keys{$name} = $fields[-1];
    }
}
close SKH;

my @nodes = expand_range($range);
for my $node (@nodes) {
    # verify key for $node
    my $filename = SKH_DIR . substr($node, -2) . "/$node/ssh_host_key.pub";
    open my $fh, $filename or do {
        print "WARN: $filename: $!\n";
        next;
    };
    my $line = <$fh>;
    close $fh;
    my $key = (split(' ', $line))[2];
    
    if (not exists $keys{$node}) {
        print "WARN: $node - no skh key in /etc/ssh/ssh_known_hosts\n";
        next;
    }
    if ($key ne $keys{$node}) {
        printf("ERROR: $node %s %s\n", substr($key,0,16), substr($keys{$node},0,16));
    }
}

__END__

=head1 NAME

    chk_skh - Check SSH Keys

=head1 SYNOPSIS

    chk_skh [options] 
     Options:
       -help            brief help message
       -man             full documentation
       -range=<range>   use the specified range

=head1 OPTIONS

=over 8

=item B<-range=seco_range>

This argument is required. Verify that the hosts specified by the seco range <seco_range>
have the same keys on jumpstart as they do in the /etc/ssh/known_hosts file.

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<chk_skh> will verify that the given nodes have the right keys in jumpstart.
It does this by comparing the keys on /usr/local/jumpstart/skh to /etc/ssh/ssh_known_hosts

=cut
