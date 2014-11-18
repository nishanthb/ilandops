package Seco::Jumpstart::Filesystem;

use 5.006;
use strict;
use warnings;
use Seco::Jumpstart::Utils qw(:all);

our $VERSION = '1.0.0';

sub new {
    my $class = shift;
    my $cfg = shift;
    
    my $self = { 
        msg => [ ],
        cfg => $cfg 
    };
    
    $self->{mkfs_script} = [ ];
    $self->{fstab} = '';
    
    # these are keyed by disks
    $self->{disksize} = {};
    $self->{parted_script} = {};
    
    # these are keyed by partitions
    $self->{oldsize} = {};
    $self->{oldstart} = {};
    $self->{oldpartype} = {};
    
    # these are keyed by mountpoints
    $self->{partition} = {};
    $self->{lazyformat} = {};
    $self->{minsize} = {};
    $self->{maxsize} = {};
    $self->{parttype} = {};
    $self->{filesystem} = {};
    $self->{fstaboptions} = {};
    $self->{mkfsoptions} = {};
    $self->{size} = {};
    $self->{start} = {};
    
    $self->{extended_start} = '';
    $self->{extended_size} = '';
    
    bless $self, $class;
    
    System("rm -f /dev/root");
    $self->get_disks;

    return $self;
}

sub error {
    my $self = shift;
    
    push @{$self->{msg}}, @_;
    return undef;
}

sub poperrors {
    my $self = shift;
    
    my @msg = @{$self->{msg}};
    $self->{msg} = [ ];
    return @msg;
}

sub get_disks {
    my $self = shift;
    
    open my $p, "/proc/partitions" or die "/proc/partitions: $!";
    my $header = <$p>; # discard header
    while (<$p>) {
        chomp; next unless $_;
        my ($major, $minor, $blocks, $name) = split;
        next unless $minor % 16 == 0;
        $self->{disksize}->{$name} = $blocks / 1024; 
    }
    close $p;
}

sub get_partition_info {
    my $self = shift;
    
    my @disks = $self->disks;
    foreach my $disk (@disks) {
        my $result = `sh -c /sbin/parted /dev/$disk print | tail +4 | head -2`;
        my @lines = split /\n/, $result;
        foreach my $line (@lines) {
            chomp;
            my ($part, $start, $size, $type) = split;
            $self->{oldsize}->{$part} = $size;
            $self->{oldstart}->{$part} = $start;
        }
    }
}

sub devname {
    my $self = shift;
    my ($disk, $part) = @_;
    if ($disk =~ /\d$/) {
        return $disk . "p" . $part;
    } else {
        return $disk . $part;
    }
}

sub parse_diskconfig {
    my $self = shift;
    my @diskconfig = @{$self->{cfg}->{diskconfig}};
    
    my $i = 0;
    my $swapseen = 0;
    my $disk;
    my ($logpartno, $primpartno, $lastprespart);
    my %seen;
    foreach my $line (@diskconfig) {
        $i++;
        $line =~ s/#.*$//;
        next if $line !~ /\S/;
        
        # disk_config - command
        if($line =~ /^disk_config(.*)/i){
            my $rest = $1;

            if ($rest =~ / end/i){
                $disk = "";
            } else {
                $rest =~ m{ (/dev/)?([\w/]+)}i
                  or return $self->error('format error in diskconfig line $i');
                $disk = $2;
                defined($seen{$disk}) 
                  and return $self->error("disk $disk already defined " .
                                          "in diskconfig line $i");
                
                $seen{$disk} = 1;
                
                defined($self->{disksize}->{$disk})
                  or return $self->error("Size not defined for $disk");
                
                $logpartno = 4;
                $primpartno = 0;
                $lastprespart = "";
            }
        }
        
        next unless $disk; # really this should be an error-out scenario
        
        if ($line =~ /^(primary|logical)\s+(.*)$/i) {
            my $part_type = $1;
            my $rest = $2;
            my $options = '';
            if ($rest =~ /(.*?)\s*;\s*(.*)$/) {
                $rest = $1;
                $options = $2;
            }
            
            my ($mountpoint, $size, $fstaboptions) = split /\s+/, $rest;
            $mountpoint =~ /^\/.*|^swap$|^-$/i
              or return $self->error("format error in diskconfig line " .
                                     "$i");
            # swap0, swap1, etc
            if ($mountpoint eq 'swap') {
                $mountpoint .= $swapseen++;
            }
            
            # check for dupe mount
            if ($mountpoint =~ /\// && $self->{partition}->{$mountpoint}) {
                return $self->error("mountpoint $mountpoint already " .
                                    "seen at diskconfig line $i");
            }
            
            
            # boot off / device
            $self->{BOOT_DEVICE} = $disk if($mountpoint eq '/');
            
            $fstaboptions = 'sw' if($mountpoint eq "swap");
            $fstaboptions = 'defaults' if($mountpoint =~ /^\//);
            
            # set a default filesystem
            my $fs = $self->{cfg}->get('def_fs');
            
            if ($options =~ s/\b(ext[23]|swap|reiser|xfs)\b//i) {
                $fs = $1;
            }
            
            if($options =~ s/\blazyformat\b//i) {
                $self->{lazyformat}->{$mountpoint} = 1;
            }
            
            $fs = "swap" if $mountpoint =~ /^swap/;
            $self->{filesystem}->{$mountpoint} = $fs;
            
            $self->{yesraid}->{$mountpoint} = 1 
              if($options =~ /-m 1/);

            # primary or logical?
            if ($part_type eq "primary") {
                $primpartno++;
                
                return $self->error("Too many primaries at diskconfig " .
                                    "line $i") 
                  if ($primpartno > 4);
                $self->{partition}->{$mountpoint} =
                  $self->devname($disk, $primpartno);
                $self->{noraid}->{$self->devname($disk, $primpartno)} = 1 
                  if($options =~ /-m 0/);
                
                # handle setting bootable
                if ($options =~ s/\bboot\b//i) {
                    return $self->error("More than one boot partition " .
                                        "at diskconfig line $i")
                      if ($self->{BOOT_PARTITION});
                    $self->{BOOT_PARTITION} = 
                      $self->{partition}->{$mountpoint};
                    $self->{BOOT_DEVICE} = $disk;
                }
            } else {            # part_type eq 'logical'
                # can't boot off a logical
                return $self->error("Cannot boot off logical partition " .
                                    "at diskconfig line $i")
                  if ($options =~ s/\bboot\b//i);
                
                return $self->error("Not enough room for extended partition ")
                  if($primpartno >= 4);
                
                $logpartno++;
                $self->{partition}->{$mountpoint} =
                  $self->devname($disk, $logpartno);
                $self->{noraid}->{$self->devname($disk, $logpartno)} = 1 
                  if($options =~ /-m 0/);
            }
            
            if ($size =~ /^(\d*)(\-?)(\d*)$/) {
                my ($min, $max);
                
                $min = $1;
                $min ||= 1;
                $max = $3;
                
                $self->{minsize}->{$mountpoint} = $min;
                if ($2 eq "-") {
                    if ($max =~ /\d+/) {
                        $self->{maxsize}->{$mountpoint} = $max;
                    } else {
                        $self->{maxsize}->{$mountpoint} = 
                          $self->{disksize}->{$disk};
                    }
                } else {
                    $self->{maxsize}->{$mountpoint} = 
                      $self->{minsize}->{$mountpoint};
                }
                
                return $self->error("Sizing error at diskconfig line $i") 
                  if $self->{minsize}->{$mountpoint} > 
                    $self->{disksize}->{$disk};
                return $self->error("Sizing error at diskconfig line $i")
                  if $self->{minsize}->{$mountpoint} > 
                    $self->{maxsize}->{$mountpoint};
                
                return $self->error("Sizing error at diskconfig line $i")
                  if $self->{minsize}->{$mountpoint} < 1;
            }
            
            # fstaboptions
            $self->{fstaboptions}->{$mountpoint} = $fstaboptions;
            
            # extra options
            $self->{parttype}->{$mountpoint} = 83;
            $self->{parttype}->{$mountpoint} = 82
              if($self->{filesystem}->{$mountpoint} eq 'swap');
            
            $self->{mkfsoptions}->{$mountpoint} = $options;
        }
    }
    
    return 1;
}

sub set_group_position {
    my $self = shift;
    my $disk = shift;
    
    my @mountpoints = $self->mountpoints($disk);
    
    my $start = 0;
    my $end = $self->{disksize}->{$disk};
    my $totalsize = $end - $start + 1;
    
    my ($mintotal, $maxmintotal) = (0, 0);
    
    foreach my $mountpoint (@mountpoints) {
        $mintotal += $self->{minsize}->{$mountpoint};
        $maxmintotal += ($self->{maxsize}->{$mountpoint} - 
                         $self->{minsize}->{$mountpoint});
        $self->{size}->{$mountpoint} = $self->{minsize}->{$mountpoint};
    }
    
    # Test if partitions fit
    return $self->error("Mountpoints do not fit for $disk")
      if($mintotal > $totalsize);
    
    # Maximize partitions
    my $rest = $totalsize - $mintotal;
    $rest = $maxmintotal if ($rest > $maxmintotal);
    
    if($rest > 0) {
        foreach my $mountpoint (@mountpoints) {
            $self->{size}->{$mountpoint} +=
              int ((($self->{maxsize}->{$mountpoint} - 
                     $self->{minsize}->{$mountpoint}) * $rest) / $maxmintotal);
        }
    }
    
    # compute rest
    $rest = $totalsize;
    foreach my $mountpoint (@mountpoints) {
        $rest -= $self->{size}->{$mountpoint};
    }
    
    # Minimize rest
    foreach my $mountpoint (@mountpoints) {
        if (($rest > 0) && 
            ($self->{size}->{$mountpoint} < 
             $self->{maxsize}->{$mountpoint})) {
            $self->{size}->{$mountpoint}++;
            $rest--;
        }
    }
    
    # Set start for every partition
    foreach my $mountpoint (@mountpoints) {
        $self->{start}->{$mountpoint} = $start;
        $start += $self->{size}->{$mountpoint};
    }
}

sub disks {
    my $self = shift;
    my $sizes = $self->{disksize};
    return sort keys %$sizes;
}

sub build_new_partitions {
    my $self = shift;
    
    my @disks = $self->disks;
    
    foreach my $disk (@disks) {
        my @mountpoints = $self->mountpoints($disk);
        $self->set_group_position($disk);
        foreach my $mountpoint (@mountpoints) {
            # now only for logicals
            next if ($self->mountpoint_is_primary($mountpoint));
            if ($self->{partition}->{$mountpoint} eq "${disk}5") {
                # partition with number 5 is first logical partition 
                # and start of extended partition
                $self->{extended_start} =
                  $self->{start}->{$mountpoint};
            }
        }
        $self->calculate_extended_size($disk);
    }
    if(!$self->{BOOT_PARTITION}) {
        $self->{BOOT_PARTITION} = $self->{partition}->{'/'};
    }
    return 1;
}

sub calculate_extended_size {
    my $self = shift;
    my $disk = shift;
    
    # get outta here unless we actually have some logicals
    return 1 unless $self->{extended_start};
    
    my @mountpoints = $self->mountpoints($disk);
    
    my $ext_end = $self->{extended_start};
    
    foreach my $mountpoint (@mountpoints) {
        next if($self->mountpoint_is_primary($mountpoint));
        
        my $new_end = ($self->{start}->{$mountpoint} +
                       $self->{size}->{$mountpoint});
        $ext_end = $new_end if($new_end > $ext_end);
    }
    $self->{extended_size} = $ext_end - $self->{extended_start} + 1;
}

sub get_parted_scripts {
    my $self = shift;
    
    my @disks = $self->disks;
    foreach my $disk (@disks) {
        my @mountpoints = $self->mountpoints($disk);
        
        my $tabletype = 'msdos';
	foreach my $mountpoint (@mountpoints) {
	    my $start = $self->{start}->{$mountpoint};
	    my $size = $self->{size}->{$mountpoint};
	    $tabletype = 'gpt' if(($start + $size) > (1024*1024*2-1));    
	}
        
        $self->{parted_script}->{$disk} =
          "parted -s /dev/$disk mklabel $tabletype\n";
        
        foreach my $mountpoint (@mountpoints) {
            my $part = $self->{partition}->{$mountpoint};
            $part =~ s/(\d+)$//;
            my $part_num = $1;
            
            my $type = ($part_num < 5 ? 'primary' : 'logical');
            # pad out remaining primaries so we can put logical at 5,...
            if($part_num == 5) {
                # make extended partition
                $self->{parted_script}->{$disk} .=
                  "parted -s /dev/$disk mkpart extended " .
                    $self->{extended_start} . " " .
                      ($self->{extended_start} +
                       $self->{extended_size}) . "\n";
            }
        	my $fs = $self->{filesystem}->{$mountpoint};
            $fs = 'linux-swap' if($fs eq 'swap');
        	$fs = 'ext2' unless($fs eq 'linux-swap');
            $self->{parted_script}->{$disk} .=
              "parted -s /dev/$disk mkpart $type $fs " .
                $self->{start}->{$mountpoint} . " ".
                  ($self->{size}->{$mountpoint} + 
                   $self->{start}->{$mountpoint}).
                    "\n";
        }
    }
    return 1;
}

sub run_parted {
    my $self = shift;
    my $scripts = $self->{parted_script};
    
    foreach my $disk (sort keys %$scripts) {
        print STDERR "INFO: Partitioning $disk...";
        my @lines = split /\n/, $scripts->{$disk};
        foreach my $line (@lines) {
            System($line);
            if($? != 0) {
                print STDERR "ERROR!\n\n";
            } else {
                print STDERR "OK\n";
            }
        }
    }
    return 1;
}

sub run_mkfs {
    my $self = shift;
    
    my @script = @{$self->{mkfs_script}};
    
    foreach my $cmd (@script) {
        System("sh -c \"$cmd\"");
    }
    
    return 1;
}

sub mountpoints {
    my $self = shift;
    my $disk = shift;
    
    my @mountpoints;
    my $partition = $self->{partition};
    
    foreach my $mountpoint (sort { $partition->{$a} cmp $partition->{$b} } 
                            keys %$partition) {
        push @mountpoints, $mountpoint
          if($self->{partition}->{$mountpoint} =~ /^$disk/);
    }
    
    return @mountpoints;
}

sub mountpoint_is_primary {
    my $self = shift;
    my $mountpoint = shift;
    
    my $device = $self->{partition}->{$mountpoint};
    $device =~ /(\d)$/ or return undef;
    return ($1 < 5) ? 1 : 0;
}

sub get_mkfs_script {
    my $self = shift;
    my $cfg = $self->{cfg}; 
    my @disks = $self->disks;

    my @mountpoints;
    foreach my $disk (@disks) {
        push @mountpoints, $self->mountpoints($disk);
    }
    
    my @cmd; 
    # line em up
    foreach my $mountpoint (@mountpoints) {
        my $filesystem = $self->{filesystem}->{$mountpoint};
        my $device = $self->{partition}->{$mountpoint};

        $cfg->set('bootdevice', "/dev/$device") if($mountpoint eq '/');
        
	next if($cfg->get('rootonly') && $mountpoint ne '/');
        # don't format if lazyformat and part not moved
        next if($filesystem !~ /^swap\d?$/ &&
                $self->{lazyformat}->{$mountpoint} &&
                ($self->{oldsize}->{$device} ==
                 $self->{size}->{$mountpoint}) &&
                ($self->{oldstart}->{$device} ==
                 $self->{start}->{$device}));
        
        # don't format if we're just going to swraid it anyway
        # next if($self->{yesraid}->{$mountpoint});
        
        if($filesystem =~ /^swap\d?$/) {
            push @cmd, "mkswap /dev/$device";
            push @cmd, "swapon /dev/$device";
        } elsif($filesystem eq 'ext2') {
            push @cmd, "mke2fs $self->{mkfsoptions}->{$mountpoint} -q -j -L " . 
              label_for_mountpoint($mountpoint) . " /dev/$device";
        } elsif($filesystem eq 'ext3') {
            push @cmd, "mke2fs $self->{mkfsoptions}->{$mountpoint} -q -j -L " .
              label_for_mountpoint($mountpoint) . " /dev/$device";
        } elsif($filesystem eq 'xfs') {
            push @cmd, "mkfs.xfs $self->{mkfsoptions}->{$mountpoint} -f " .
              "/dev/$device";
        } elsif($filesystem eq 'reiser') {
            push @cmd, "mkreiserfs $self->{mkfsoptions}->{$mountpoint} -q " .
              "/dev/$device";
        }
    }

    $self->{mkfs_script} = \@cmd;
}

sub get_fstab {
    my $self = shift;
    
    my $fstab = <<EOF;
# /etc/fstab: static file system information.
#
#<file sys>          <mount point>     <type>   <options>   <dump>   <pass>
EOF

    my @disks = $self->disks;
    my @mountpoints;
    foreach my $disk (@disks) {
        push @mountpoints, $self->mountpoints($disk);
    }
    foreach my $mountpoint (@mountpoints) {
        my $filesystem = $self->{filesystem}->{$mountpoint};
        my $device = $self->{partition}->{$mountpoint};
        my $fstaboptions = $self->{fstaboptions}->{$mountpoint};
        my $zeroone = ($filesystem eq '/' ? 1 : 0);
        
        $mountpoint = 'none' if($mountpoint =~ /^swap/);
        $fstab .= 
          "/dev/$device $mountpoint $filesystem $fstaboptions 0 $zeroone\n";
    }

    $fstab .= "none /proc proc defaults 0 0\n";
    $self->{fstab} = $fstab;

    return 1;
}

sub copy_fstab {
    my $self = shift;
    
    my $fstab = $self->{fstab};
    
    open my $fh, ">/tmp/fstab";
    print $fh $fstab;
    close $fh;

    return 1;
}

sub run_scripts {
    my $self = shift;
    my $cfg = $self->{cfg}; 
    
    my $error = 0;
    
    unless($cfg->get('rootonly')) {
        $error += $self->run_parted;
    } 

    $error += $self->run_mkfs;
    $error += $self->copy_fstab;
    
    return $error;
}

sub generate_scripts {
    my $self = shift;
    my $cfg = $self->{cfg}; 
    my $error = 0;
    
    $error += $self->parse_diskconfig;
    unless($cfg->get('rootonly')) {
        $error += $self->build_new_partitions;
        $error += $self->get_parted_scripts;
    } 

    $error += $self->get_mkfs_script;
    $error += $self->get_fstab;

    return $error;
}


