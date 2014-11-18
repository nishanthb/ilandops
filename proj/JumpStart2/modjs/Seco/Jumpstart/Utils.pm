package Seco::Jumpstart::Utils;

use 5.006;
use strict;
use warnings 'all';

use Socket;
use Exporter;
use Term::ReadKey;

our $VERSION   = "1.0.0";
our @ISA       = ('Exporter');
our @EXPORT_OK = qw(crapout displaybold set_status System write_file
  read_file run_local figlet os need_args optional_shell
  installstep get_hostname label_for_mountpoint
  needs_siteops_fix min kernel get_modules_from_pci
  list_physical_disks file_has
);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);
our @EXPORT = ();

sub label_for_mountpoint {
    my $mountpoint = shift;
    my $label;
    if ($mountpoint eq "/") {
        $label = "/";
    }
    else {
        my $last = uc((split '/', $mountpoint)[-1]);
        $label = substr($last, 0, 16) if $last;
    }
    return $label;
}

sub list_physical_disks {
    open my $p, "/proc/partitions" or die "/proc/partitions: $!";
    my $header        = <$p>;    # discard header
    my @physicaldisks = ();
    while (<$p>) {
        chomp;
        next unless $_;
        my ($major, $minor, $blocks, $name) = split;
        next unless $minor % 16 == 0;
        push @physicaldisks, $name;
    }

    return @physicaldisks;
}

sub get_hostname {
    my $ip    = shift;
    my $iaddr = inet_aton($ip);
    return gethostbyaddr($iaddr, AF_INET);
}

sub need_args {
    my $hashref = shift;
    my @needs   = @_;

    my $success = 1;

    foreach my $need (@needs) {
        if (!defined($hashref->{$need})) {
            $success = 0;
            displaybold("!! Missing $need\n");
        }
    }

    return $success;
}

sub get_modules_from_pci {
    my $class = shift;

    my %classmap = (eth => [ 'eepro100', 'e1000', 'tg3' ]);

    my $list = $classmap{$class}
      or return undef;

    my @modules = ();
    my @out     = `/sbin/pcimodules`;
    foreach my $line (@out) {
        chomp;
        foreach my $mod (@$list) {
            push @modules, $line if ($line eq $mod);
        }
    }

    return @modules;
}

sub os {
    return "redhat" if (-e "/mnt/etc/redhat-release");
    return "debian" if (-e "/mnt/etc/debian_version");
    return "unknown";
}

sub kernel {
    open my $file, "</mnt/etc/redhat-release" or return "2.4";
    my $str = <$file>;
    close $file;

    return "2.6" if ($str =~ "release 4");
    return "2.4";
}

sub crapout {
    set_status("ERROR: @_\n");
    displaybold("ERROR: ");
    print @_, "\n";
    system("sh");
    die @_ . "\n";
}

sub installstep {
    my @time = localtime();
    my $now =
      sprintf('%d/%d %02d:%02d:%02d', $time[4] + 1, @time[ 3, 2, 1, 0 ]);

    displaybold("\n$now *) ", @_, "\n");
    set_status("$now *) ", @_, "\n");

    print "Press 'X' if you want a shell...";
    ReadMode 3;    # cbreak
    while (1) {
        my $key = ReadKey(1);
        unless (defined $key) {
            # restore terminal settings and return if timer expired
            ReadMode 1;
            print "\n";
            return;
        }
        last if $key eq "X";
    }

    ReadMode 1;
    print "\n";
    system("/bin/sh");
}

sub displaybold {
    print "[1m";
    print @_;
    print "[0m";
}

sub set_status {
    open(STATUS, ">/tmp/status") || return;
    print STATUS "@_\n";
    close STATUS;
}

sub System {
    my $cmd = shift;
    print "Running: [$cmd]\n";
    system($cmd);
    if ($? != 0) {
        print "ERROR: Exit code $?\n";
    }
    return $?;
}

sub write_file {
    my ($file, $content) = @_;
    open my $fh, ">$file" or die "$file: $!";
    print $fh $content;
    close $fh;
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

sub run_local {
    my (@list) = @_;
    my $pwd = `pwd`;
    chomp $pwd;
    print "$pwd # @list\n";
    system @list;
    my $exit_value  = $? >> 8;
    my $signal_num  = $? & 127;
    my $dumped_core = $? & 128;
    print "(Exit=$exit_value)\n"   if ($exit_value);
    print "(Signal $signal_num)\n" if ($signal_num);
    print "(Dumped core)\n"        if ($dumped_core);
    return $exit_value;
}

sub figlet {
    my $msg = shift;
    print "\n\n";
    system("figlet", $msg);
    print "\n\n";
}

sub warning {

    # May want this to go to all terminals - ie, display, serial, etc.
    print STDERR @_;
}

sub optional_shell {
    open my $tty, "/dev/tty" or return;
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm 5;
        my $buffer;
        my $blah = sysread $tty, $buffer, 1;
        alarm 0;
    };
    close $tty;
    if ($@) {

        # propagate unexpected errors
        die unless $@ eq "alarm\n";
        print "\n";
    }
    else {

        # a shell
        system("sh");
    }
}

sub needs_siteops_fix {
    print "\nFeel free to reboot/power cycle this machine"
      . " to correct the problems found.\n";
    system("/bin/sh");
    exit(1);
}

sub min {
    my $min = shift;
    $min = $_ < $min ? $_ : $min for @_;
    return $min;
}

sub file_has {
    my $filename = shift;
    my $pattern  = shift;
    my $result   = 0;
    open my $fh, "<$filename" or do {
        warn "$filename: $!";
        return;
    };
    while (<$fh>) {
        if (/$pattern/) {
            $result = 1;
            last;
        }
    }
    close $fh;
    return $result;
}

1;
