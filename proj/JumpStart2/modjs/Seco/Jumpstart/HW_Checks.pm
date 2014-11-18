package Seco::Jumpstart::HW_Checks;

use 5.006;
use strict;
use warnings 'all';
use Seco::Jumpstart::Utils qw(:all);

our $VERSION = '1.0.0';

sub new {
    my ($class, $cfg) = @_;

    my $self = { 
        msg => "",
        cfg => $cfg 
    };
    bless $self, $class;
}

sub safe_dmidecode {
    my $self = shift;
    return `dmidecode`;
}

sub test_ipmi {
    my $self = shift;
    my $cfg = $self->{cfg};
    my $ipmi = lc($cfg->get('ipmi_enabled'));

    return 1 if $ipmi eq "*";
    my $dmi = $self->safe_dmidecode;
    return 1 unless $dmi;
    my $setting;
    if ($dmi =~ /Out-of-band Remote Access.*Inbound Connection:\s+(\w+)/msi) {
        $setting = lc($1);
    } else {
        print "WARNING: Unknown IPMI setting\n";
        return 1;
    }
    if ($setting eq "enabled" and $ipmi = "no") {
        figlet("IPMI enabled");
        print "\nWe don't want ipmi enabled on this machine.\n";
        needs_siteops_fix();
        $self->{msg} = "IPMI enabled (profile says it shouldn't.)";
        return;
    } elsif ($setting eq "disabled" and $ipmi = "yes") {
        figlet("IPMI disabled");
        $self->{msg} = "IPMI disabled (profile says we want it enabled)";
        print "\nWe want ipmi enabled on this machine.\n";
        needs_siteops_fix();
        return;
    }
    return 1;
}

sub test_cpu {
    my $self = shift;
    
    $self->count_cpus or return 0;
    $self->check_hyperthreading or return 0;
    
    return 1;
}

sub count_cpus {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    my $should_have = $cfg->get('cpus');
    return 1 if $should_have eq "*";

    my $have = $self->get_physical_cpus;
    if ($should_have != $have) {
        if ($should_have > $have) {
            figlet("Missing CPU");
            $self->{msg} = "ERROR: This host should have $should_have " .
              "CPUs but it has $have instead.\n";
            set_status("ERROR  --cpu=${have}/$should_have");
            needs_siteops_fix();
            return 0;
        } else {
            $self->{msg} = "WARNING: I was expecting $should_have CPUs," .
              "but I have $have instead!\n";
            return 1; # this is OK
        }
    }

    $self->{msg} = "Number of CPUs detected is OK ($have)\n";
    return 1;
}

sub get_physical_cpus {
    my $self = shift;
    
    # caching
    return $self->{_pcpus} if defined $self->{_pcpus};

    local $_ = $self->safe_dmidecode;
    return 1 unless $_;

    # get the Version: string after a DMI type 4

    my @versions =
      map { s/\s+$//; $_ }
      /^Handle \s+ \w+ \s+  # Handle #
        DMI \s type \s 4      # We're only interested in DMI type 4
        .*?                   # and let's skip things we don't care about
        \s+ Version: \s       # now we're near the good stuff
        ([^\n]+)              # our version
        /gsmx;

    my %cpus;
    my $total_cpus = 0;
    for (@versions) {
        next if /^0+$/;
        next if /^\s*$/;
        $cpus{$_}++;
        $total_cpus++;
    }

    $self->{_pcpus} = $total_cpus;
    return $total_cpus;
}

sub check_hyperthreading {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    my $ht = lc($cfg->get('hyperthreading'));
    return 1 if $ht eq "*";

    $ht = ($ht eq "1") || ($ht eq "enabled") || 
        ($ht eq "on") || ($ht eq "yes");
    my $logical_cpus  = $self->get_logical_cpus();
    my $physical_cpus = $self->get_physical_cpus();

    my $error = 0;
    my $expected_logical_cpus = ( 1 + $ht ) * $physical_cpus;
    if ( $logical_cpus < $expected_logical_cpus ) {
        figlet("Enable Hyperthreading");
        $self->{msg} = "This host does not have hyperthreading enabled,\n" .
          "which is required for this config\n";
        set_status("ERROR  please enable hyperthreading");
        return 0;
    } elsif ( $logical_cpus > $expected_logical_cpus ) {
        figlet("Disable Hyperthreading");
        $self->{msg} = "This host has hyperthreading enabled, " .
          "but it should be disabled for this config.\n";
        set_status("ERROR  please disable hyperthreading");
        return 0;
    } else {
        $self->{msg} = "Hyperthreading settings OK\n";
        return 1;
    }

    return 1;
}

sub get_mem {
    my $memory = `free|sed -n 2p`;
    if ($memory =~ /Mem:\s+(\d+)/) {
        $memory = $1;
    } else {
        warn "Memory: $memory\n";
        return;
    }
    $memory /= 1000 * 1000.0;
    return sprintf( "%.1fG", $memory );
}

sub test_memory {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    my $have = get_mem();
    my $should_have = $cfg->get('memory');
    for ($have, $should_have) {
        s/G$//;
    }
   
    if ($have < $should_have) {
        figlet("Memory: $have");
        $self->{msg} = "This host should have $should_have of RAM, " .
          "but it only has $have.\n";
        set_status("ERROR  --memory=$have/$should_have");
        return 0;
    } elsif ( $have gt $should_have ) {
        displaybold( "Warning: Was expecting only $should_have, "
                     . "but this machine has $have of RAM.\n" );
        sleep(1);
    } else {
        $self->{msg} = "Memory: OK ($have)\n";
        return 1;
    }
    return 1;
}

sub test_disk {
    my $self = shift;
    my $cfg = $self->{cfg};
    my $hostname = $cfg->get('hostname');
    return 1 unless ($cfg->get('burnin') and $cfg->get('force'));
    
    # This is run as part of the burnin test.
    # Create a meaningful status file after running zapsector
    
    my $min_speed = $cfg->get('min_disk_speed');
    my $max_threads = $cfg->get('zapsector_threads');
    $max_threads ||= 8;
    my $cmd = "/usr/local/bin/zapsectoralldev.sh -r -ts $min_speed " .
        "-m $max_threads";
    print "BURNIN: $cmd\n";
    my $err = system($cmd); 
    my ( $year, $month, $day, $hour, $min ) = (localtime)[ 5, 4, 3, 2, 1 ];
    $year += 1900;
    $month++;
    my $fmt_date =
      sprintf( '%d%02d%02d-%02d:%02d', $year, $month, $day, $hour, $min );
    
    my $status = $err ? "FAILED" : "PASSED";
    open my $fh, ">/tmp/zapsector.status" or die "zapsector: $!";
    print $fh "$hostname $fmt_date $status\n";

    opendir my $dir, "." or die ".: $!";
    my @devices = map { /^chk\.(\w+)\.log$/; $1 }
      grep { /^chk.*log$/ } readdir($dir);
    closedir $dir;
    for my $dev (@devices) {
        open my $ifh, "<chk.$dev.log" or die "chk.$dev.log: $!";
        my @lines = <$ifh>;
        close $ifh;

        chomp(@lines);
        for (@lines) {
            print $fh "$dev: $_\n";
        }
    }
    print $fh "__END__\n";
    close $fh;

    system("nc boothost 8765 < /tmp/zapsector.status");
    if ($status eq "FAILED") {
        $self->{msg} = "Zapsector failed";
        figlet("disk errors");
        print "\nZapsector failed - take a look at " .
          "http://postal.inktomisearch.com/~seco/cores/zapsector/index.cgi\n";
        needs_siteops_fix();
        return;
    }
    return 1;
}

sub get_logical_cpus {
    my $self = shift;
    
    # caching
    return $self->{_lcpus} if defined $self->{_lcpus};

    open my $cpuinfo, "<", "/proc/cpuinfo" or die "/proc/cpuinfo: $!";
    my $result = grep { /processor\s+:\s*\d+\s*$/ } <$cpuinfo>;
    close $cpuinfo;

    $self->{_lcpus} = $result;
    return $result;
}

1;
