#!/usr/local/bin/perl -w
#
package OSDependant;

use strict;
use vars qw/@ISA @EXPORT/;
require Exporter;
@ISA = qw(Exporter);

@EXPORT = qw/get_pkill_cmd handle_mem get_free_mem 
    proc_running
    get_disk_busy handle_swap/;

# this is a lot faster than ps, which might take an obscene amount of time
# if there are many threads which is common on nodes running idpd
sub proc_running {
    my $procname = shift;
    local *PROC; local *FH;
    local $_;
    opendir PROC, "/proc" or die "ERROR: /proc $!\n";
    while ($_ = readdir PROC) {
        next unless -d "/proc/$_" && /^\d+$/;
        # read the name of the process
        open FH, "/proc/$_/stat" or 
            warn "WARNING: /proc/$_/stat: $!\n" and next; 
        my $stat = <FH>;
        defined($stat) or warn "WARNING: reading stat $!";
        return 1 if "($procname)" eq (split ' ', $stat)[1];
        close FH;
    }
    closedir PROC;
    return;
}

sub get_pkill_cmd {
    return $^O eq 'linux' ? 'killall' : 'pkill';
}

sub handle_mem {
    $^O eq 'linux' ? handle_linux_mem() : handle_solaris_mem();
}

sub handle_linux_mem {
    local $_;
    local *MEM;
    open MEM, "/proc/meminfo" or die "ERROR: /proc not mounted?: $!\n";
    while (<MEM>) {
        print;
        last if $. > 2;
    }
    close MEM or die "ERROR: closing mem: $!\n";
}

sub handle_solaris_mem {
    print "ERROR: NOT IMPLEMENTED\n";
}

sub get_free_mem {
    $^O eq 'linux' ? get_linux_free_mem() : get_solaris_free_mem();
}

sub get_linux_free_mem {
    local *MI;
    open MI, "/proc/meminfo" or die "ERROR: opening /proc/meminfo: $!\n";
    <MI>; # discard first line
    my $mem = <MI>;
    my $swap = <MI>;
    close MI or die "ERROR: closing /proc/meminfo: $!\n";

    my ($memtotal, $memused) = $mem =~ /^Mem:\s+(\d+)\s+(\d+)/;
    my ($swaptotal, $swapused) = $swap =~ /^Swap:\s+(\d+)\s+(\d+)/;

    my $total = $memtotal + $swaptotal;
    my $free = $total - $memused - $swapused;

    return 100.0 * $free / $total;
}

# TODO
sub get_solaris_free_mem {
    return -1;
}

sub get_disk_busy {
    $^O eq 'linux' ? get_linux_disk_busy() : get_solaris_disk_busy();
}

sub get_linux_disk_busy {
    local *IOSTAT;
    local $_;

    open IOSTAT, "/usr/bin/iostat -x 10 2|" or die "ERROR: iostat: $!";
    # discard all the crap we get until the second round
    my $round = 0;
    while (<IOSTAT>) {
        $round++ if /^Device:/;
        last if $round == 2;
    }
    my $max_busy = 0;
    while (<IOSTAT>) {
        my $busy = (split)[-1];
        next unless $busy;
        $max_busy = $busy if $busy > $max_busy;
    }
    close IOSTAT or die "ERROR: closing iostat\n";
    return $max_busy;
}

# TODO
sub get_solaris_disk_busy {
    return -1;
}

sub handle_linux_swap {
    local $_;
    local *MEM;
    open MEM, "/proc/meminfo" or die "/proc not mounted?";
    my ($total, $free);
    while (<MEM>) {
        if (/^Swap:/) {
           (undef, $total, undef, $free) = split;
           last;
        }
    }
    close MEM or die;
    return unless defined $total and defined $free;

    $total /= 1024 * 1024;
    $free /= 1024 * 1024;
    printf "%d MB/%d MB\n", $free, $total;
}

# TODO
sub handle_solaris_swap {
    print "ERROR: NOT IMPLEMENTED\n";
}

sub handle_swap {
    $^O eq 'linux' ? handle_linux_swap() : handle_solaris_swap();
}

