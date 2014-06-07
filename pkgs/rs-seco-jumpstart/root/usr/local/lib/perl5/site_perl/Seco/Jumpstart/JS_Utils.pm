package Seco::Jumpstart::JS_Utils;

require Exporter;

use strict;
use warnings 'all';
use constant CF_DIR => "/usr/local/jumpstart/conf";

use Carp;
use YAML;
use Socket;
use Seco::AwesomeRange qw/:all/;
use Seco::Jumpstart::Logger;

our @ISA       = qw/Exporter/;
our @EXPORT_OK = qw/get_ip read_file write_file read_big_file
  fqdn dns_read_warnings dns_reset_warnings WWWDATA/;

sub WWWDATA () {
    -f "/etc/redhat-release" ? "apache" : "www-data";
}
my ($uid, $gid) = (getpwnam(WWWDATA))[ 2, 3 ];

sub write_file {
    my ($file, $msg) = @_;
    open my $fh, ">$file" or die "$file: $!";
    print $fh $msg;
    close $fh;
    chown $uid, $gid, $file;
}

sub read_file {
    my $file = shift;
    sysopen my $fh, $file, 0 or do {
        warn "$file: $!\n";
        return;
    };
    sysread $fh, my $results, -s $fh || 4096;    # use 4k for /proc files
    close $fh;
    return $results;
}

sub fqdn {
    my $host = shift;
    my $fqdn = $host;
    if ($host !~ /\.(?:com|org|net)$/) {

        # not a fqdn
        $fqdn = "$host.inktomisearch.com";
    }

    return $fqdn;
}

# Make sure nobody can access %hosts_ip but us
{
    my %hosts_ip;
    my %cnames;
    my %hosts_warnings;

    sub dns_reset_warnings {
        %hosts_warnings = ();
    }

    sub dns_read_warnings {
        return %hosts_warnings ? compress_range(keys %hosts_warnings) : undef;
    }

    # Read tinydns data
    sub _dns_read {
        open my $data, "<", "/service/tinydns/root/data"
          or die "Can't open tinydns data: $!";
        while (<$data>) {
            if (/^\+([^.]+)\.(inktomisearch|inktomi)\.com:([^:]+):0/) {
                $hosts_ip{$1} = $3;
            }
            elsif (/^\+([^:]+):([^:]+):0/) {

                # FQDN that's not inktomi/inktomisearch
                $hosts_ip{$1} = $2;
            }
            elsif (/^C([^:]+):([^:]+):0/) {

                # CNAME
                my ($node, $real_name) = ($1, $2);
                $real_name =~ s/\.$//;
                $cnames{$node} = $real_name;
                if ($node =~ /^([^.]+).inktomisearch\.com$/) {
                    $cnames{$1} = $real_name;
                }
            }
        }
        close $data;
    }

    sub get_ip {
        my ($node) = @_;
        confess "Need a hostname" unless $node;

        _dns_read() unless %hosts_ip;
        $node = $cnames{$node} while exists $cnames{$node};
        return $hosts_ip{$node} if exists $hosts_ip{$node};

        if ($node ne fqdn($node)) {

            # if this is not a fqdn
            $hosts_warnings{$node}++;
        }

        my $addr = scalar gethostbyname($node);
        Seco::Jumpstart::Logger->getLogger("error", "Can't resolve $node!\n")
          and return "0.0.0.0"
          unless $addr;
        return inet_ntoa($addr);
    }
}

sub read_big_file {
    my $filename = shift;
    open my $fh, "<", $filename or die "$filename: $!";
    my @lines;
    while (<$fh>) {
        if (/^\$INCLUDE\s+"([^"]+)"/) {
            push @lines, read_big_file(CF_DIR . "/$1");
        }
        else {
            push @lines, $_;
        }
    }
    return wantarray() ? @lines : join("", @lines);
}
1;
