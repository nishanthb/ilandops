###### jumpstart disk configuration
###### reads a structure of this form:
# cciss:
#     c0:
#         d0:
#             raidtype: raid1
#             physicaldisks: 5
#     c1:
#         d0:
#             raidtype: raid10
#             physicaldisks: all
#
# blockdev:
#     - scsidisk0:
#         candidates: [ 'cciss/c0d0', sda ]
#
#     - scsidisk1:
#         candidates: [ sda, sdb ]
#         partitions:
#             - part1:
#                 minsize: 100G
#                 fstype: ext3
#                 mountpoint: /var
#                 mountopts: defaults
#                 label: VAR
#             - part2:
#                 size: 100G
#
#
#     - scsidisk2:
#         candidates: [ sda, sdc ]
#         partitions:
#             - part1:
#
# swraid:
#     md0:
#         raidtype: raid0
#         partitions:
#             - [ scsidisk1, part1 ]
#             - [ scsidisk2, part1 ]
#
#     md2:
#         fstype: ext3
#         raidtype: raid1
#         swraids: [ md0, md1 ]
#         partitions:
#           - [ scsidisk0, part0 ]

package Seco::Jumpstart::Disk;

use 5.006;
use strict;
use warnings 'all';
use Seco::Jumpstart::Utils qw(:all);
use YAML;

our $VERSION = '1.0.0';

sub new {
    my ($class, $cfg) = @_;
    
    eval { $cfg->{disklayout} = YAML::Load(loader($cfg->{diskconfig})) };
    return undef if($@);
    return undef unless($cfg->{disklayout});
    
    my $self = bless { cfg => $cfg }, $class;
    
    my $uname = `uname -m`;
    if($uname =~ /x86_64/) {
        $self->{twcli} = "/usr/sbin/tw_cli.x86_64";
    } else {
        $self->{twcli} = "/sbin/tw_cli";
    }
    
    return $self;
}

sub count_drives {
    my $self = shift;
    my $cfg = $self->{cfg};
    my $ndisks = $cfg->get('disks');
    
    my @reals = $self->get_physical_disks;
    unless(scalar @reals >= $ndisks) {
        figlet("Disk errors");
        crapout("Wanted $ndisks disks, found " . (scalar @reals));
    }
}

sub loader {
    my ($confref) = (@_);
    my $yaml;
    $yaml .= "$_\n" for(@$confref);
    return $yaml;
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

sub setup_raids {
    my $self = shift;
    my $cfg = $self->{cfg};
    my $raidtype = $self->raidtype;
	if ($raidtype eq 'cciss') {
		$self->break_cciss;
		$self->make_jbod_cciss;
	}
	if ($raidtype eq '3ware') {
		$self->break_tware;
		$self->make_jbod_tware;
	}
	$self->count_drives;
        $self->set_wce;
	$self->break_cciss if($raidtype eq 'cciss');
	$self->break_tware if($raidtype eq '3ware');
    $self->make_adaptec if($raidtype eq 'adaptec');
    $self->make_cciss if($raidtype eq 'cciss');
    $self->make_tware if($raidtype eq '3ware');
    $self->make_lsi if($raidtype eq 'lsi');
}

sub setup_rest {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    $self->generate_scripts;
    $self->run_scripts;
    $self->deposit_fstab;
}

sub setup {
    my $self = shift;
    my $cfg = $self->{cfg};
    $self->setup_raids;
    $self->count_drives;
    $self->setup_rest;
}

sub make_adaptec {
    my $self = shift;
    return $self->error("I don't know how to build adaptec yet!");
}

sub raidtype {
    my $self = shift;
    
    return "adaptec" if(-d "/proc/scsi/aacraid");
    
    open my $scsi, "</proc/scsi/scsi";
    my @list = <$scsi>;
    close $scsi;
    
    foreach (@list) {
        return "lsi" if /Vendor: MegaRAID/i;
	return "3ware" if /Vendor: AMCC/;
	return "3ware" if /Vendor: 3ware/;
    }
    
    open my $modules, "</proc/modules";
    @list = <$modules>;
    close $modules;
    
    foreach (@list) {
	return "3ware" if(/^3w_9xxx/);
	return "3ware" if(/^3w_xxxx/);
        return "cciss" if (/^cciss/);
    }
    
    return "3ware" if(-d "/proc/scsi/3w-9xxx");
    
    open my $part, "</proc/partitions";
    my @pts = <$part>;
    close $part;

    my @out = grep { /cciss/ } @pts;
    return "cciss" if scalar(@out) > 0;

    return "none";
}

sub cciss_clear_controller {
    my $self = shift;
    my $controller = shift;
    $controller =~ s/^c//;

    System("/usr/sbin/hpacucli controller slot=$controller delete forced");

    return 1;
}

sub cciss_count_drives {
    my $self = shift;
    my $controller = shift;
    $controller =~ s/^c//;

    open my $proc,
      "/usr/sbin/hpacucli controller slot=$controller physicaldrive all show|";
    my $drives = 0;

    while(<$proc>) {
	next unless /physicaldrive\s+(.?.?:?\d+:\d+)/;
	$drives++;
    }
    close $proc;

    return $drives;
}

sub cciss_get_free_drives {
    my $self = shift;
    my $controller = shift;
    $controller =~ s/^c//;

    open my $proc, "/usr/sbin/hpacucli controller slot=$controller " .
      "physicaldrive allunassigned show|";
    my @physicaldrives = ();
    while(<$proc>) {
	next unless /physicaldrive\s+(.?.?:?\d+:\d+)/;
	push @physicaldrives, $1;
    }
    close $proc;

    return @physicaldrives;
}

sub tware_get_units {
    my $self = shift;
    my $controller = shift;
    my $twcli = $self->{twcli};
    open my $proc, "yes | $twcli info $controller|";
    my @units = ();
    while(<$proc>) {
	next unless /^(u\d+)\s/;
	push @units, $1;
    }
    close $proc;

    return @units;
}

sub tware_clear_controller {
    my $self = shift;
    my $controller = shift;
    my @units = $self->tware_get_units($controller);
    my $twcli = $self->{twcli};

    foreach my $unit (@units) {
	System("yes | $twcli /$controller/$unit del");
    }
}

sub tware_get_free_drives {
    my $self = shift;
    my $controller = shift;
    my $twcli = $self->{twcli};
    open my $proc, "yes | $twcli info $controller|";
    my @drives = ();
    while(<$proc>) {
	next unless /^p(\d+)\s+OK\s+\-\s/;
	push @drives, $1;
    }
    close $proc;

    return @drives;
}

sub round {
    my $number = shift;
    return int($number + 0.5);
}

sub tware_unit_size {
    my $self = shift;
    my ($controller, $unit) = @_;
    my $twcli = $self->{twcli};

    open my $tw_show, "$twcli /$controller/$unit show|";
    my $capacity = 0;
    while (<$tw_show>) {
	next unless /^u\d+\s/;
	print;
	$capacity = (split)[-1];
    }
    close $tw_show;

    # return the capacity in GB
    return $capacity / (2.0 * 1024 * 1024);
}

sub get_jbod_name {
    my $cur_name = shift;
    my ($tw9, $tw);
    open my $pci, "lspci -n|" or return $cur_name;
    while (<$pci>) {
        $tw++ if /13c1:100[01]/;
        $tw9++ if /13c1:100[23]/;
    }
    close $pci;
    $tw ||= 0; $tw9 ||= 0;
    if ($tw > $tw9) {
        return "JBOD";
    } else {
        return "single";
    }
}

sub jbod_lsi {
    System("/tmp/megarc.bin -EachDskRaid0  -a0 WB RAA CIO");
}

sub setup_lsi {
    my $devices = `cat /proc/devices`;
    if ($devices =~ /(\d+)\s+megadev/) {
        my $major = $1;
        System("mknod /dev/megadev0 c $major 0");
        System("echo 'GET /tftpboot/megarc.bin' | nc boothost 9999 > /tmp/megarc.bin");
        System("chmod +x /tmp/megarc.bin");
    } else {
        print "WARNING: Couldn't find an LSI controller\n";
    }
}

sub make_lsi {
    my $self = shift;
    my $lsi = $self->{cfg}->{disklayout}->{'lsi'};
    $self->setup_lsi unless -x "/tmp/megarc.bin";
    for my $adapter (keys %$lsi) {
        print "Configuring LSI Adapter $adapter:\n";
        my $config = $lsi->{$adapter}{config};
        if (lc($config) eq 'jbod') {
            $self->jbod_lsi;
        } else {
            my @cmds = @$config;
            my $first_cmd = shift @cmds;
            System("/tmp/megarc.bin -newCfg -a0 $first_cmd");
            for my $cmd (@cmds) {
                System("/tmp/megarc.bin -addCfg -a0 $cmd");
            }
        }
    }
    System("rmmod megaraid_mbox; rmmod megaraid_mm");
    sleep(1);
    System("modprobe megaraid_mbox");
    system("cat /proc/partitions");
}

sub break_tware {
    my $self = shift;
    my $tware = $self->{cfg}->{disklayout}->{'3ware'};
    my $twcli = $self->{twcli};

    foreach my $controller (keys %$tware) {
        $self->tware_clear_controller($controller);
    }
}

sub make_jbod_tware {
	my $self = shift;
    my $tware = $self->{cfg}->{disklayout}->{'3ware'};
    my $twcli = $self->{twcli};

    foreach my $controller (keys %$tware) {
		my $ctrl_def = $tware->{$controller};
		my @physicaldisks = $self->tware_get_free_drives($controller);
		foreach my $disk (@physicaldisks) {
			my $raidtype = get_jbod_name();
			System("yes | $twcli /$controller add " .
			   "type=$raidtype disk=$disk");

			System("$twcli /$controller rescan");
                }
		system("$twcli /$controller set autocarve=off");

		System("$twcli /$controller rescan");
		system("sync;sync");
    }
}

sub make_tware {
    my $self = shift;
    my $tware = $self->{cfg}->{disklayout}->{'3ware'};
    my $twcli = $self->{twcli};

    foreach my $controller (keys %$tware) {
	my $ctrl_def = $tware->{$controller};
	my @units = sort grep { /^u\d/ } keys %$ctrl_def;
	my @physicaldisks = $self->tware_get_free_drives($controller);
	foreach my $unit (@units) {
	    my $raidtype = lc $ctrl_def->{$unit}{raidtype};
	    my $spare_disks = $ctrl_def->{$unit}{spares} || 0;
	    my $need_disks = $ctrl_def->{$unit}{physicaldisks};
	    $need_disks = @physicaldisks - $spare_disks if $need_disks eq 'all';
	    if (($need_disks + $spare_disks) > @physicaldisks) {
		$need_disks .= "+$spare_disks spares" if $spare_disks;
		return $self->error("Need $need_disks, have " .
				    scalar @physicaldisks . " left")
	    }

	    my @usedisks;
	    push @usedisks, shift @physicaldisks while $need_disks--;
            if ($raidtype eq 'jbod' or $raidtype eq 'single') {
                $raidtype = get_jbod_name();
            }
	    System("yes | $twcli /$controller add " .
		   "type=$raidtype disk=" . (join ':', @usedisks));

	    # add spares
	    for (1 .. $spare_disks) {
		my $port = $physicaldisks[$_ - 1];
		System("$twcli /$controller/p$_ export quiet");
	    }
	    System("$twcli /$controller rescan");
	    for (1 .. $spare_disks) {
		my $port = shift @physicaldisks;
		System("$twcli /$controller add type=spare disk=$port");
	    }

	    System("$twcli /$controller rescan");
	}
	my $autocarve = $ctrl_def->{autocarve};
	if ($autocarve) {
	    # autocarve is a number [1024,2048] or 'auto'
	    System("$twcli /$controller set autocarve=on");
	    if ($autocarve eq "auto") {
		$autocarve = round($self->tware_unit_size($controller, "u0") / 2.0);
		$autocarve = 1024 if $autocarve < 1024;
		$autocarve = 2048 if $autocarve > 2048;
	    }
	    if ($autocarve >= 1024 and $autocarve <= 2048) {
		System("$twcli /$controller set carvesize=$autocarve");
	    } else {
		$self->error("tw_cli carvesize must be between 1024 and 2048");
	    }
	} else {
            system("$twcli /$controller set autocarve=off");
        }

	System("$twcli /$controller rescan");
	system("sync;sync");
    }
}

sub break_cciss {
    my $self = shift;
    my $cciss = $self->{cfg}->{disklayout}->{cciss};

    foreach my $controller (keys %$cciss) {
		$self->cciss_clear_controller($controller);
    }
}

sub make_jbod_cciss {
    my $self = shift;
    my $cciss = $self->{cfg}->{disklayout}->{cciss};

    foreach my $controller (keys %$cciss) {
        my @physicaldisks = $self->cciss_get_free_drives($controller);

        my $hpcontroller = $controller;
        $hpcontroller =~ s/^c//;

        for my $disk (@physicaldisks) {
            System("/usr/sbin/hpacucli controller slot=$hpcontroller " .
                   "create type=logicaldrive drives=$disk raid=0");
        }

        system("sync;sync");
    }
}

sub make_cciss {
    my $self = shift;
    my $cciss = $self->{cfg}->{disklayout}->{cciss};

    foreach my $controller (keys %$cciss) {
	my $disks = $cciss->{$controller};
	foreach my $disk (keys %$disks) {
	    my $raidtype = lc $disks->{$disk}->{raidtype};
	    my @physicaldisks = $self->cciss_get_free_drives($controller);

	    my $need_disks = $disks->{$disk}->{physicaldisks};
	    $need_disks = scalar @physicaldisks if($need_disks eq 'all');

	    return $self->error("Need $need_disks, have " .
				scalar @physicaldisks . " left")
	      unless $need_disks <= scalar @physicaldisks;

	    my @usedisks;
	    push @usedisks, shift @physicaldisks while($need_disks--);

	    $raidtype =~ s/raid//;
	    $raidtype =~ s/10/1+0/;

	    my $hpcontroller = $controller;
	    $hpcontroller =~ s/^c//;

	    if($raidtype eq 'jbod') {
                for (@usedisks) {
                    System("/usr/sbin/hpacucli controller slot=$hpcontroller " .
                           "create type=logicaldrive drives=$_ raid=0");
                }
	    } else {
		System("/usr/sbin/hpacucli controller slot=$hpcontroller " .
		       "create type=logicaldrive drives=" .
		       (join ',', @usedisks) . " raid=$raidtype");
	    }

	    system("sync;sync");
	}
    }
}

sub get_scripts {
    my $self = shift;
    my @scripts;

    foreach my $script (qw(parted mkfs)) {
	foreach my $device (keys %{$self->{$script}}) {
	    next unless $self->{$script}->{$device};
	    push @scripts, @{$self->{$script}->{$device}};
	}
    }

    foreach my $script (qw(raid_parted raid_mdadm raid_mkfs)) {
	next unless $self->{$script};
	push @scripts, @{$self->{$script}};
    }

    return @scripts;
}

sub deposit_mdadm_conf {
    my $self = shift;
    my $mdadm = $self->get_mdadm_conf();
    
    open my $rtb, ">/tmp/mdadm.conf";
    print $rtb $mdadm;
    close $rtb;
}

sub deposit_fstab {
    my $self = shift;
    my $cfg = $self->{cfg};

    my $fstab = $self->get_fstab();

    open my $fst, ">/tmp/fstab.local";
    print $fst $fstab;
    close $fst;
    

    if (lc($cfg->get('nfs_home')) eq "yes" or $cfg->get('nfs_home') =~ m!^/!) {

	my $home_mount_point;
	if ($cfg->get('nfs_home') =~ m!^/!) {
	  $home_mount_point = $cfg->get('nfs_home');
        } else {
          $home_mount_point = "/home";
        }

        if ($fstab =~ m(\s/home\s)) {
            $home_mount_point = "/adminhome";
            mkdir "/mnt/$home_mount_point";
        }

    $fstab .= "adminhost:/export/home $home_mount_point nfs ".
              "rsize=8192,wsize=8192,hard,intr,rw,noatime 0 0\n";
    }

    $fstab .= <<EOF;
none /dev/pts devpts gid=5,mode=620 0 0
none /proc proc defaults 0 0
none /dev/shm tmpfs defaults 0 0
EOF
    
    open $fst, ">/tmp/fstab.disk";
    print $fst $fstab;
    close $fst;

    open $fst, ">/tmp/fstab";
    print $fst $fstab;
    close $fst;

    return 1;
}

sub get_mdadm_conf {
    my $self = shift;
    my $mdadm = "";
    
    foreach my $line (@{$self->{raid_mdadm_conf}}) {
	$mdadm .= $line . "\n";
    }
    
    return $mdadm;
}

sub get_fstab {
    my $self = shift;
    
    my $fstab = "";
    
    foreach my $device (keys %{$self->{fstab}}) {
	foreach my $line (@{$self->{fstab}->{$device}}) {
	    $fstab .= $line . "\n";
	}
    }
    
    foreach my $line (@{$self->{raid_fstab}}) {
	$fstab .= $line . "\n";
    }
    
    return $fstab;
}

sub run_scripts {
    my $self = shift;
    my @scripts = $self->get_scripts;
    
    foreach my $cmd (@scripts) {
	if(System("sh -c \"$cmd\"") != 0) {
            crapout("Disk: $cmd failed");
        }
    }
}

sub generate_scripts {
    my $self = shift;
    my $cfg = $self->{cfg};
    my $blockdevs = $cfg->{disklayout}->{blockdev};
    
    my %parted_scripts;
    my %blockdev;
    
    foreach my $deviceref (@$blockdevs) {
	my ($device) = keys %$deviceref;
	my $disk = $self->get_candidate($deviceref->{$device}->{candidates});
	defined($disk) or return undef;
	my $disksize = $self->get_disk_size($disk);
	my $taken = 0;
	my $requested = 0;
	my $partitions = $deviceref->{$device}->{partitions};
	my $filldisks = 0;
        
	# pass 1: figure out how much we NEED
	foreach my $partition (@$partitions) {
	    my ($name) = keys %$partition;
            
	    if(my $minsize = $partition->{$name}->{minsize}) {
		$filldisks++;
                
		$minsize =~ s/G$/000/i;
		$minsize =~ s/M$//i;
		return $self->error("invalid minimum disk size $minsize")
		  if $minsize =~ /\D/;
		$requested  += $minsize;
	    } else {
		my $size = $partition->{$name}->{size};
		$size =~ s/G$/000/i;
		$size =~ s/M$//i;
		return $self->error("Size not specified for $name")
		  unless defined $size;
		return $self->error("Invalid partition size $size")
		  if $size =~ /\D/;
                
		$taken += $size;
	    }
	}
        
	return $self->error("Not enough free disk space: $taken + $requested " .
			    "is less than $disksize")
	  if($taken + $requested > $disksize);
        
	# >2TB partition tables need gpt
	my $tabletype = 'msdos';
	$tabletype = 'gpt' if($disksize > (1024*1024*2-1));
	my @parted = ("parted -s /dev/$disk mklabel $tabletype");
	push @parted, "sync;sleep 1;sync";
        
	my @mkfs = ();
	my @fstab = ();
        
	my $extra = $disksize - $taken - $requested; # how much is left over
	$extra /= ($filldisks || 1); # have to share
        
	my $startpos = "0%";
        
	# pass 2: actually allocate the disk sizes
	my $i = 0;
	foreach my $partition (@$partitions) {
	    my ($name) = keys %$partition;
	    $i++;
            
	    my $partno = $i;
	    $partno++ if($i >= 4 and scalar @$partitions > 4);
	    my $pname = partition_name($disk, $partno);
	    $self->{pname}->{$device}->{$name} = $pname;
	    my ($pnum) = $pname =~ /(\d+)$/;
            
	    my $size;
            
	    if($partition->{$name}->{minsize}) {
		$size = $partition->{$name}->{minsize};
		$size =~ s/G$/000/i;
		$size =~ s/M$//i;
		$size += $extra;
	    } else {
		$size = $partition->{$name}->{size};
		$size =~ s/G$/000/i;
		$size =~ s/M$//i;
	    }
            
	    my $type = 'primary';
	    if(scalar @$partitions > 4 and $i > 3) {
		$type = 'logical';
		push @parted,
		  "parted -s /dev/$disk mkpart extended $startpos $disksize"
		    if($i == 4);
	    }
            
	    push @parted,
	      "parted -s /dev/$disk mkpart $type $startpos " .
		($startpos + $size);
	    $startpos += $size;
            
	    if(my $fstype = lc $partition->{$name}->{fstype}) {
		my $mkfsopts = $partition->{$name}->{mkfsopts} || '';
		my $label = $partition->{$name}->{label} || '';
		$mkfsopts .= " -L $label" if($label);

                if($cfg->get('rootonly') and $fstype ne 'swap') {
                    next unless(defined($partition->{$name}->{mountpoint}) and
                                $partition->{$name}->{mountpoint} eq '/');
                }
                
                # nuke disk labels (bz#2116048)
                push @mkfs, "dd if=/dev/zero of=/dev/$pname count=4096";

		if($fstype eq 'ext3') {
		    push @mkfs, "mke2fs -q -j $mkfsopts /dev/$pname";
                    push @mkfs, "tune2fs -O +dir_index /dev/$pname";
		} elsif($fstype eq 'ext2') {
		    push @mkfs, "mke2fs -q $mkfsopts /dev/$pname";
		} elsif($fstype eq 'swap') {
		    push @mkfs, "mkswap $mkfsopts /dev/$pname";
		    push @mkfs, "swapon /dev/$pname";
		    push @mkfs,
                      "parted -s /dev/$disk set $pnum swap on || echo cool";
		    push @fstab, "/dev/$pname none swap pri=1 0 0";
		} elsif($fstype eq 'xfs') {
		    push @mkfs, "mkfs.xfs $mkfsopts -f /dev/$pname";
		} elsif($fstype eq 'reiser' or $fstype eq 'reiserfs') {
		    push @mkfs, "mkreiserfs $mkfsopts -q /dev/$pname";
		}
                
		if(my $mountpoint = $partition->{$name}->{mountpoint}) {
		    my $mountopts = $partition->{$name}->{mountopts} ||
		      "defaults";
		    my $mountdev = "/dev/$pname";
                    
                    if($mountpoint eq '/') {
                        $cfg->set('bootdevice', $mountdev);
                        $cfg->set('def_fs', $fstype);
                        open my $file, ">>/jumpstart/overrides.txt";
                        print $file "root-device=$mountdev\n";
                        print $file "default-fs=$fstype\n";
                        close $file;
                    }
                    
                    $mountdev = "LABEL=$label" if($label);
                    
		    push @fstab, "$mountdev $mountpoint $fstype $mountopts 0 0"
		}
	    }
	}
        
	$self->{mkfs}->{$device} = \@mkfs;
	$self->{parted}->{$device} = \@parted;
	$self->{fstab}->{$device} = \@fstab;
	$self->{used_disk}->{$device} = $disk;
    }
    
    my @raid_parted = ();
    my @raid_mkfs = ();
    my @raid_mdadm = ();
    my @raid_fstab = ();
    my @raid_mdadm_conf = ();
    
    our %raiddeps = ();
    my @satisfied_raid;
    # generate raid dependency list
    foreach my $raid (keys %{$self->{cfg}->{disklayout}->{swraid}}) {
	my $ref = $self->{cfg}->{disklayout}->{swraid}->{$raid};
	if(my $swref = $ref->{swraids}) {
	    $raiddeps{$raid} = $swref;
	} else {
	    $raiddeps{$raid} = [];
	}
    }

    our @buildorder;
    sub below {
	my $raid = shift;
	my @seen = @_;

	foreach (@seen) {
	    return undef if($raid eq $_);
	}

	foreach (@buildorder) {
	    return 1 if($_ eq $raid);
	}

	below($_, $raid, @_) for (@{$raiddeps{$raid}});
	push @buildorder, $raid;
	return 1;
    }
    
    foreach my $raid (keys %raiddeps) {
	below($raid) or
	  return $self->error('unsatisfiable raid graph for $raid');
    }
    
    foreach my $raid (@buildorder) {
	my $ref = $self->{cfg}->{disklayout}->{swraid}->{$raid};
	my $fstype = lc $ref->{fstype} || '';
        
        if($cfg->get('rootonly') and $fstype ne 'swap') {
            next unless(defined($ref->{mountpoint}) and
                        $ref->{mountpoint} eq '/');
        }
        
        my @parts;
        my $partitions = $ref->{partitions};
	foreach my $partition (@$partitions) {
	    my ($device, $partlabel) = @$partition;
	    my $pname = $self->{pname}->{$device}->{$partlabel};
	    my $disk = $self->{used_disk}->{$device};
            
	    my ($pnum) = $pname =~ /(\d+)$/;
            
	    push @raid_parted, "parted /dev/$disk set $pnum raid on";
	    push @parts, "/dev/$pname";
	}
        
        my $swraids = $ref->{swraids};
        foreach my $swraid (@$swraids) {
            push @parts, "/dev/$swraid";
        }
        
	my $raidtype = $ref->{raidtype};
	$raidtype =~ s/raid//i;
	my $mkfsopts = $ref->{mkfsopts} || '';
	my $chunksize = $ref->{chunksize} || '128';
        
	if(my $label = $ref->{label}) {
	    $mkfsopts .= " -L $label";
	}
        
        # nuke disk labels (bz#2116048)
        push @raid_mkfs, "dd if=/dev/zero of=/dev/$raid count=4096";

	if($fstype eq 'ext3') {
	    push @raid_mkfs, "mke2fs -q -j $mkfsopts /dev/$raid";
	} elsif($fstype eq 'ext2') {
	    push @raid_mkfs, "mke2fs -q -j $mkfsopts /dev/$raid";
	} elsif($fstype eq 'swap') {
	    push @raid_mkfs, "mkswap $mkfsopts /dev/$raid";
	} elsif($fstype eq 'xfs') {
	    push @raid_mkfs, "mkfs.xfs $mkfsopts -f /dev/$raid";
	} elsif($fstype eq 'reiser' or $fstype eq 'reiserfs') {
	    push @raid_mkfs, "mkreiserfs $mkfsopts -q /dev/$raid";
	}
        
	if(my $mountpoint = $ref->{mountpoint}) {
	    my $mountopts = $ref->{mountopts} || "defaults";
            
	    my $label = $ref->{label};
	    my $mountdev = "/dev/$raid";
            
            if($mountpoint eq '/') {
                $cfg->set('bootdevice', $mountdev);
                $cfg->set('def_fs', $fstype);
                open my $file, ">>/jumpstart/overrides.txt";
                print $file "root-device=$mountdev\n";
                print $file "default-fs=$fstype\n";
                close $file;
            }
	    $mountdev = "LABEL=$label" if($label);
            
	    push @raid_fstab, "$mountdev $mountpoint $fstype $mountopts 0 0"
	}
        
	push @raid_mdadm, "yes | mdadm -C /dev/$raid -l $raidtype " .
	  ($chunksize ? "-c $chunksize " : "") . "-n " . scalar @parts .
	    " @parts";
        push @raid_mdadm_conf, "ARRAY /dev/$raid level=$raidtype num-devices=" . scalar @parts . " devices=" . (join ',', @parts);
    }
    
    $self->{raid_parted} = \@raid_parted;
    $self->{raid_mkfs} = \@raid_mkfs;
    $self->{raid_mdadm} = \@raid_mdadm;
    $self->{raid_fstab} = \@raid_fstab;
    $self->{raid_mdadm_conf} = \@raid_mdadm_conf;
    
    return 1;
}

sub partition_name {
    my $disk = shift;
    my $partno = shift;
    
    if($disk =~ /^hd\w$/ or $disk =~ /sd\w/) {
	return "$disk$partno";
    } elsif($disk =~ m#^cciss/#) {
	return $disk . 'p' . $partno;
    }
    
    return undef;
}


sub get_candidate {
    my $self = shift;
    my $candidates = shift;
    
    my @cands;
    
    if(ref $candidates) { # a list of explicit candidates
	@cands = @$candidates;
    } else { # a magic word
	if(lc $candidates eq 'scsi') {
	    @cands = ( 'sda' .. 'sdz' );
	} elsif(lc $candidates eq '3ware') {
	    @cands = ( 'sda' .. 'sdz' );
	} elsif(lc $candidates eq 'ide') {
	    @cands = ( 'hda' .. 'hdz' );
	} elsif(lc $candidates eq 'cciss') {
	    my @phys = $self->get_physical_disks;
	    @cands = grep { /cciss/ } @phys;
	} elsif((lc $candidates eq 'any') or
                (lc $candidates eq 'all')) {
	    my @phys = $self->get_physical_disks;
	    @cands = grep { $_ !~ /md/ } @phys;
        }
    }
    
    my $disk = undef;
    my @possible = $self->get_unused_disks;
    
    foreach my $cand (@cands) {
	foreach (@possible) {
	    if($cand eq $_) {
		$disk = $cand;
		last;
	    }
	}
	last if($disk);
    }
    
    defined($disk) or return $self->error("No candidate disks found for " .
					  (join ' ', @cands));
    
    $self->{used_disks}->{$disk} = 1;
    return $disk;
}

sub get_physical_disks {
    my $self = shift;
    
    if(!defined $self->{physicaldisks}) {
        my @physicaldisks = list_physical_disks();
	$self->{physicaldisks} = \@physicaldisks;
    }

    return @{$self->{physicaldisks}};
}

sub get_unused_disks {
    my $self = shift;
    my @disks = $self->get_physical_disks;

    my @newdisks;
    foreach (@disks) {
	push @newdisks, $_ unless $self->{used_disks}->{$_};
    }

    return @newdisks;
}

sub get_disk_size {
    my $self = shift;
    my $disk = shift;

    my $result = undef;

    open my $p, "/proc/partitions" or die "/proc/partitions: $!";
    my $header = <$p>; # discard header

    while (<$p>) {
	chomp; next unless $_;
	my ($major, $minor, $blocks, $name) = split;
	next unless $minor % 16 == 0;
	next unless $name eq $disk;

	$result = $blocks / 1024;
	last;
    }
    close $p;

    return $result;
}

sub get_partition_info {
    my $self = shift;
    my $disk = shift;

    my @partitions;

    my $result = `sh -c /sbin/parted /dev/$disk print | tail +4 | head -2`;
    my @lines = split /\n/, $result;
    foreach my $line (@lines) {
	chomp;
	my ($part, $start, $size, $type) = split;

	push @partitions, [ $part, $start, $size, $type ];

	$self->{oldsize}->{$part} = $size;
	$self->{oldstart}->{$part} = $start;
    }
}

sub set_wce {
    my $self = shift;

    my @phys = $self->get_physical_disks;
    s#^#/dev/# for @phys;
    my ($e) = grep(-x,"/usr/bin/sdparm","/sbin/sdparm");
    System("$e --set=WCE --save @phys");
}
