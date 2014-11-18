package Seco::Jumpstart::Raid;

use 5.006;
use strict;
use warnings 'all';
use Seco::Jumpstart::Utils qw(:all);
use Seco::Jumpstart::Filesystem;

our $VERSION = '1.0.0';

sub new {
    my ($class, $cfg) = @_;
    
    my $self = bless { cfg => $cfg }, $class;
    my $uname = `uname -m`;
    if($uname =~ /x86_64/) {
       $self->{twcli} = "/usr/sbin/tw_cli.x86_64";
    } else {
       $self->{twcli} = "/sbin/tw_cli";
    }

    return $self;
}

sub setup {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    if($cfg->get('rootonly')) {
        my $filesystem = Seco::Jumpstart::Filesystem->new($cfg);
        $filesystem->generate_scripts
          or print "Error: ", @{$filesystem->{msg}};
        $filesystem->run_scripts
          or print "Error: ", @{$filesystem->{msg}};
    } else {
    	$self->configure_hwraid if $cfg->is('hwraid');
        $self->count_drives;
        $self->set_wce;
        $self->partition_drives;

        my $filesystem = Seco::Jumpstart::Filesystem->new($cfg);
        $filesystem->generate_scripts
          or print "Error: ", @{$filesystem->{msg}};
        $filesystem->run_scripts
          or print "Error: ", @{$filesystem->{msg}};
        $self->{noraid} = $filesystem->{noraid};
        $self->configure_swraid if $cfg->is('softwareraid');
    }
}

sub test_before_raid {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    return $cfg->get('hwraid') ne 'no' && $cfg->get('force');
}

sub configure_hwraid {
    my $self = shift;
    my $cfg = $self->{cfg};
    my $twcli = $self->{twcli};
 
    if ( $self->this_is_an_hp_box ) {
        $self->configure_hpraid_new;
        return;
    } elsif ($self->this_is_an_adaptec_sata_box) {
        $self->configure_adaptec_sata;
        return;
    }
    
    my $hwraid = $cfg->get('hwraid');
    my @hwraid = split( ';', $hwraid );
    my @controllers = $self->get_tw_controllers;
    return unless @controllers;
    
    for ( my $i = 0 ; $i < @controllers ; $i++ ) {
        if ( uc( $hwraid[$i] ) eq "JBOD" ) {
            $self->configure_jbod_single($controllers[$i]);
            next;
        }
        
        my $controller = $controllers[$i];
        my $cmd        = "$twcli info c$controller";
        print "Running: $cmd\n";
        $_ = `$cmd`;
        my @units = /^u(\d+)\s+/gm;
        for my $unit (@units) {
            System("$twcli maint deleteunit c$controller u$unit");
        }
        
        $hwraid = $hwraid[$i];
        my $spare = ( $hwraid =~ /SPARES:(\d+)/ )[0];
        $hwraid =~ s/SPARES:\d+//;
	$cmd = "$twcli maint rescan c$controller";
	System($cmd);

        $cmd = "$twcli maint createunit c$controller $hwraid";
        System($cmd);
        
        # TODO: Do something with spares
        $_ = `$twcli info c$controller`;
        my @free_ports = /^p(\d+)\s+OK\s+-[^\n]+/mg;
        
        $spare = 0 unless defined($spare);
        for ( 1 .. $spare ) {
            my $port = $free_ports[ $_ - 1 ];
            System("$twcli maint remove c$controller p$port");
        }
	$cmd = "$twcli maint rescan c$controller";
	System($cmd);
        for ( 1 .. $spare ) {
            my $port = $free_ports[ $_ - 1 ];
            System("$twcli maint createunit c$controller rspare p$port ");
        }

    }
    foreach my $controller (@controllers) {
        system("$twcli maint rescan c$controller");
    }
    system("sync;sync;sleep 1");
    
    return 1;
}

sub guess_swraid_mountpoint {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    my $diskconfig = $cfg->get('diskconfig');
    my $mount_point;
    my $i = 2;
    $mount_point = (split(' ', $diskconfig->[$i]))[1];
    while ($mount_point eq "swap"
        or $mount_point eq "-"
        or $mount_point eq "/" 
	or $mount_point =~ /^\s*$/ )
    {
        $i++;
        $mount_point = (split(' ', $diskconfig->[$i]))[1];
    }
    return $mount_point;
}

sub create_swraid {
    my $self = shift;
    my $level = shift; # raid level
    
    my $cfg = $self->{cfg};
    my $raid_chunk_size = $self->{cfg}->get('raid_chunk_size');
    # find the right disks
    my @partitions  = $self->get_partitions_for_swraid();
    my @dev_parts = map { "/dev/$_" } @partitions;
    my @part_sizes = map { get_partition_size($_) } @partitions;
    my $min_size = min(@part_sizes);
    for (my $i = 0; $i < @partitions; $i++) {
        repartition($partitions[$i], $min_size) 
            if $part_sizes[$i] != $min_size;
    }
    my $npart = scalar @partitions;
    
    print "* Stopping and releasing resources from /dev/md0\n";
    System("mdadm --stop /dev/md0 >/dev/null 2>&1"); 
    System("mdadm --remove /dev/md0 >/dev/null 2>&1");
    System("yes|mdadm -C /dev/md0 " .
        "-c $raid_chunk_size -l $level -n $npart @dev_parts");
    
    my $def_fs = $cfg->{def_fs};
    # nuke disk labels (bz#2116048)
    push @{$self->{filesystems}},
         "/bin/dd if=/dev/zero of=/dev/md0 count=4096";
    if ($def_fs eq "ext3") {
        push @{$self->{filesystems}},
            "/sbin/mkfs.ext2 -q -L __LABEL__ -j /dev/md0";
    } elsif ($def_fs eq "xfs" ) {
        push @{$self->{filesystems}},
            "/sbin/mkfs.xfs -f -L __LABEL__ /dev/md0";
    } else {
        push @{$self->{filesystems}},
            "/sbin/mkfs.ext2 -q -L __LABEL__ -j /dev/md0";
    }
}

sub configure_swraid {
    my $self = shift;
    my $cfg = $self->{cfg};
    my $def_fs = $cfg->get('def_fs');
    
    if ($cfg->get('rootonly')) {
        crapout("rootonly install and software raid not supported - just " .
                "dangerous to make automatic");
    }
    
    my $raid_chunk_size = $cfg->get('raid_chunk_size');
    
    my $swraid_mountpoint;
    if ( @{$self->{diskconfig}}[0] =~ /^# MD0: (\S+)/ ) {
        $swraid_mountpoint = $1;
        shift @{$cfg->{diskconfig}}; #fugly
    } else {
        $swraid_mountpoint = $self->guess_swraid_mountpoint;
    }
    $cfg->set('swraid_mountpoint', $swraid_mountpoint);
    
    my $software_raid = $cfg->get('softwareraid');
    if ($software_raid =~ /^raid(0|1|5)$/) {
        $self->create_swraid($1);
        $self->make_swraid_fs;
        return;
    }
    
    # FIXME
    # software raid 5 should try to preserve if possible
    crapout("software-raid set to '$software_raid': don't know what to do.");
    
}

sub make_swraid_fs {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    my $mount_point = $cfg->get('swraid_mountpoint');
    for my $mkfs (@{$self->{filesystems}}) {
        if ((split ' ', $mkfs)[-1] eq "/dev/md0") {
            $mkfs =~ s/__LABEL__/label_for_mountpoint($mount_point)/e;
        }
        System($mkfs);
    }
}

sub count_drives {
    my $self = shift;
    my $cfg = $self->{cfg};
    my $twcli = $self->{twcli};
 
    my @wantdisks = ( 'sda' .. 'sdz' );
    my @idedisks = ( 'hda' .. 'hdz' );
    my $idedisks = $cfg->get('idedisks');
    
    splice(@wantdisks, $cfg->get('disks'));
    
    if ($idedisks =~ /^\d/ ) {
        splice(@idedisks, $idedisks);
        @wantdisks = ( @idedisks, @wantdisks );
    }
    
    my @realdisks = $self->get_disks;
    @realdisks = sort @realdisks;
    my $hpsmart = 0;
    
    foreach my $disk (@realdisks) {
        if($disk =~ /^cciss/) {
            $hpsmart = 1;
            for (my $i = 0; $i <= $#wantdisks; $i++) {
                if($wantdisks[$i] =~ /^(sd[a-z])/) {
                    $wantdisks[$i] = $disk;
                    $self->{diskmap}->{$1} = $disk;
                    last;
                }
            }
        }
    }
    
    $self->{hpsmartarray} = $hpsmart;
    $cfg->set('hpsmartarray', $hpsmart);
    
    if($hpsmart) {
        print("Using HP Smart Array logical units.\n");
        mkdir "/tmp/sfdisk.cciss", 0777;    # for sfdisk
    }
    
    # Quick and ugly hack to ignore
    if ($idedisks eq '*') {
        @realdisks = sort grep { !/^hd[a-z]$/ } @realdisks;
    }
    
    my $wants = join( " ", sort @wantdisks ); # disks we want
    print "Want disks $wants\n";
    my $reals = join( " ", sort @realdisks ); # disks found on this machine
    print "Found disks $reals\n";
    
    # Ignore the order of hd# disks
    s/hd[a-z]/hd/g for ( $wants, $reals );
    
    unless ( $wants eq $reals ) {
        my $status = "ERROR: disk mismatch; want $wants; found $reals";
        my $hwraid = $cfg->get('hwraid');
        if ($hwraid) {
            if (not $self->this_is_an_hp_box) {
                for my $c ( 0 .. 2 ) {
                    my $cmdl =
                      "$twcli info c$c | egrep '(Model|FW|BIOS|NOT PRESENT)'";
                    my $r = `$cmdl`;
                    if ( $r =~ m/NOT PRESENT/ ) {
                        print "% $cmdl\n$r";
                        my @r = grep( /NOT PRESENT/, split( /\n/, $r ) );
                        foreach (@r) {
                            $status .= "; Replace c$c port $_";
                        }
                    }
                }
            }
        }
        figlet("Disk errors");
        if ($cfg->get('disks')) {
            
            # SCSI Drives
            print "Output of /proc/scsi/scsi:\n";
            system("cat /proc/scsi/scsi");
            
            my $scsi = `cat /proc/scsi/scsi`;
            my @id = ($scsi =~ /Id: (\d+) /g);
            if (@id) {
               $status .= "; Have scsi id(s) @id";
            }
        }
        
        print("\nThe number of disks found doesn't match what we were " .
              "expecting. We were expecting \"$wants\", but we found " .
              "\"$reals\" instead.\n");
        
        set_status($status);
        my $dev = `cat /proc/devices`;
        if ($dev =~ /(megaraid|megadev)/i) {
            sleep(300);
            system("reboot -f");
        } else {
            system("sh");
        }
    }
    $self->{diskarray} = \@realdisks;
    $cfg->set('bootdisk', $realdisks[0]);
}

sub get_disks {
    my $self = shift;
    
    my ( $major, $minor, $name, @results );
    open P, "<", "/proc/partitions" or die "/proc/partitions: $!";
    my $header = <P>;                 # discard header
    while (<P>) {
        chomp;
        next unless $_;
        ( $major, $minor, undef, $name ) = split;
        next unless $minor % 16 == 0;
        push @results, $name;
    }
    close P;
    
    unless (@results) {
        print("didnt find any disks - IDE/SCSI driver Ok?\n");
    }
    return @results;
}

sub fix_etc {
    my $self = shift;
    # Fix /etc/inittab for HP boxes
    if ( $self->this_is_an_hp_box ) {
        system('perl -pi -e "s/^T1:23/#T1:23/" /mnt/etc/inittab');
    }
}

sub this_is_an_hp_box {
    my $self = shift;
    
    my @tmpdisks = $self->get_disks;
    @tmpdisks = sort @tmpdisks;
    return $tmpdisks[0] eq "cciss/c0d0";
}

sub configure_hpraid_new {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    open my $proc, 
      "/usr/sbin/hpacucli controller slot=0 physicaldrive all show|";
    my @physicaldrives = ();
    while(<$proc>) {
        next unless /physicaldrive\s+(\d+:\d+)/;
        push @physicaldrives, $1;
    }
    close $proc;
    
    System("/usr/sbin/hpacucli controller slot=0 delete forced");
    
    if($cfg->get('hwraid') eq "JBOD") {
        for (@physicaldrives) {
            System("/usr/sbin/hpacucli controller slot=0 " .
                   "create type=logicaldrive drives=$_");
        }
    } else {
        my $raidlevel = $cfg->get('hwraid');
        $raidlevel =~ s/raid//;
	$raidlevel =~ s/10/1+0/; 
	System("/usr/sbin/hpacucli controller slot=0 " .
               "create type=logicaldrive drives=" .
               join(',', @physicaldrives) . 
	       " raid=$raidlevel");
    }
    $cfg->set(disks => 1) unless $cfg->get('hwraid') eq 'JBOD';
    
    system("sync;sync");
    sleep 5;
    system("cat /proc/partitions");
    return 1;
}

sub configure_hpraid {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    local $_;
    $_ = `printf "show volumes;\nshow disks;\n"|acu -d /dev/cciss/c0d0`;
    my @volumes = /^create volume (\d+)/mg;
    my $disks = 0;
    $disks = $1 if m{^//\s+(b\d+t\d+.*)$}m;
    crapout("Can't find disks!\n") unless $disks;
    
    my @disks = split(/,\s*/, $disks);
    if (@disks != $cfg->get('disks')) {
        figlet("Disk errors");
        crapout("Was expecting " . $cfg->get('disks') . 
                " disks in this HP array " .
                ", but I found " . (scalar @disks) . " instead.");
    }
    
    open my $acu, "|acu -d /dev/cciss/c0d0" or die "acu: $!";
    
    if (@volumes) {
        print $acu "destroy volumes ", join( ",", @volumes ), ";\n";
        sleep 5;
    }
    
    my $cmd;
    my $hwraid = $cfg->get('hwraid');
    
    if ($hwraid eq "JBOD") {
        $cmd = "";
        my $i = 0;
        for (@disks) {
            $cmd .= "create volume $i { disks ( $_ ) \n\t " .
              "redundancy = RAID0 };\n";
            $i++;
        }
    }
    else {
        $cmd =
          sprintf("create volume 0 { " . 
                  "disks ( %s )\n\t redundancy = %s };\n",
                  join( ",", @disks ), $hwraid );
    }
    
    print "Running $cmd";
    print $acu $cmd;
    close $acu;
    $cfg->set('disks', 1) unless $hwraid eq 'JBOD';
    system("sync;sync");
    sleep 5;
    system("cat /proc/partitions");
}

sub this_is_an_adaptec_sata_box {
    my $self = shift;
    
    return -d "/proc/scsi/aacraid";
}

sub adaptec_send_cmds {
    my $self = shift;
    
    my $cmds = shift;
    write_file("/tmp/cmds.aac", 
               sprintf("%s\n%s\n%s\n", 'logfile start "/tmp/cmds.log"',
                       $cmds, 'logfile end'));
    system('aaccli @/tmp/cmds.aac');
    open my $fh, "</tmp/cmds.log" or die "/tmp/cmds.log: $!";
    return $fh;
}

sub get_adaptec_controller {
    my $self = shift;
    
    # Open the controller
    my $fh = $self->adaptec_send_cmds("controller list");
    my $controller;
    while (<$fh>) {
        next unless /^([a-z]\w+)\s/;
        $controller = $1;
        last;
    }
    close $fh;
    
    unless ($controller) {
        figlet("Controller?");
        system("/bin/sh");
    }
    return $controller;
}

sub adaptec_delete_all_volumes {
    my $self = shift;
    
    my $controller = shift;
    my $cmds = <<"EOT";
open $controller
container list
EOT
    my $fh = adaptec_send_cmds($cmds);
    my @containers;
    while (<$fh>) {
	next unless /^\s*(\d+)/;
	push @containers, $1;
    }
    close $fh;
    
    $cmds = "open $controller\n";
    $cmds .= join("", map { "container delete $_\n" } @containers);
    adaptec_send_cmds($cmds);
}

sub adaptec_get_disks {
    my $self = shift;
    
    my $controller = shift;
    my $cmds = <<"EOT";
open $controller
disk list
EOT
    my $fh = adaptec_send_cmds($cmds);
    my @disks;
    while (<$fh>) {
        next unless /^\d+:(\d+):\d+/;
        push @disks, $1;
    }
    close $fh;
    return @disks;
}

sub configure_adaptec_sata {
    my $self = shift;
    my $hwraid = $self->{cfg}->get("hwraid");
    my $controller = $self->get_adaptec_controller();
    my $cmds = "open $controller\n";
    
    if ( $hwraid eq "JBOD" ) {
        $self->adaptec_delete_all_volumes($controller);
        my @disks = $self->adaptec_get_disks($controller);
        $cmds .= join("", map { "container create volume $_\n" } @disks);
    } else {
        my @volumes = split(';', $hwraid);
        $cmds .= join("", map { "container create $_\n" } @volumes);
    }
    $self->adaptec_send_cmds($cmds);
}

sub get_tw_controllers {
    my $self = shift;
    my $twcli = $self->{twcli};
 
    my $out = `$twcli info` or do {
        print "DEBUG: Can't execute tw_cli info: $!\n";
        return;
    };
    my @result = $out =~ /^c(\d+)\s+/mg or do {
        print "DEBUG: Can't parse tw_cli output: $_\n";
        return;
    };
    return @result;
}

sub configure_jbod_single {
    my $self = shift;
    my $twcli = $self->{twcli}; 
    my $controller = shift;
    
    # delete all units
    local $_;
    
    $_ = `$twcli info c$controller`;
    my @units = /^\s*Unit\s+(\d+):/gm;
    for my $unit (@units) {
        system("$twcli maint deleteunit c$controller u$unit");
    }
    
    # delete all ports
    $_ = `$twcli info c$controller`;
    my @ports = /^\s*Port\s+(\d+):/gm;
    for my $port (@ports) {
        system("$twcli maint remove c$controller p$port");
    }
    system("$twcli maint rescan c$controller");
    for my $port (@ports) {
        system("$twcli maint createunit c$controller rjbod p$port");
    }
}

sub partition_drives {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    my @new_diskconfig = ();
    
    my $onoff = 0;
    my %disks;
    my $diskarray = $self->{diskarray};
    
    %disks = map { $_ => 1 } @$diskarray;
    
    my $default_filesystem = $cfg->get('def_fs') || "ext3";
    my $diskconfig = $cfg->get('diskconfig');
    foreach my $line (@$diskconfig) {
        chomp $line;
        if ($line =~ /disk_config (\S+)\s*$/) {
            my $disk_name = $1;
            if(my $mapped = $self->{diskmap}->{$disk_name}) {
                $line =~ s/$disk_name/$mapped/;
                $disk_name = $mapped;
            }
            $onoff = defined $disks{$disk_name};
        }
        $line =~ s/lazyformat// if $cfg->get('force');
        $line =~ s/,errors=remount-ro// if $default_filesystem eq "xfs";
        
        push @new_diskconfig, $line if($onoff);
    }
    
    $self->{diskconfig} = \@new_diskconfig;
    
    return 1;
}

sub get_partitions_for_swraid {
    my $self = shift;
    
    open PART, "/proc/partitions" or die "Can't open /proc/partitions: $!\n";
    my ( @disks, @partitions );
    my %types_of_disks = ( 'sd' => 0, 'hd' => 0, 'cciss' => 0 );
    
    while (<PART>) {
        my ( undef, $minor, $size, $name ) = split;
        next unless defined $minor && $minor =~ /^\d+$/;
        if ( $minor % 16 == 0 ) {
            push @disks, $name;
            for my $type ( keys %types_of_disks ) {
                if ( $name =~ /^$type/ ) {
                    $types_of_disks{$type}++;
                }
            }
        }
        else {
            push @partitions, [ $name, $size ];
        }
    }
    close PART;
    
    # get the most popular type of disk, and use its big partitions for sw
    # raid 0
    
    my $most_popular = (sort { $types_of_disks{$b} <=> $types_of_disks{$a} }
                        keys %types_of_disks)[0];
    
    print "* Most popular type of disk: $most_popular\n";
    my @candidate_partitions =
      grep { $_->[0] =~ /^$most_popular/o } @partitions;
    
    my ( $prefix, $candidate_name, $candidate_size );
    ( $candidate_name, $candidate_size ) = @{ shift @candidate_partitions };
    ( $prefix = $candidate_name ) =~ s/\d+$//;
    
    my @results;
    
    for (@candidate_partitions) {
        my ( $name, $size ) = @{$_};
        my $this_prefix = $name;
        $this_prefix =~ s/\d+$//;
        
        if ( $this_prefix eq $prefix ) {
            if ( $size > $candidate_size ) {
                $candidate_size = $size;
                $candidate_name = $name;
            }
        } else {
            push @results, $candidate_name;
            #              unless $self->{noraid}->{$candidate_name};
            $prefix         = $this_prefix;
            $candidate_name = $name;
            $candidate_size = $size;
        }
    }
    push @results, $candidate_name
      unless $self->{noraid}->{$candidate_name};
    print "* Using partitions ", join( ",", @results ), "\n";
    
    return @results;
}

sub get_partition_size {
    my $part = shift;
    # sfdisk -s only shows size in blocks, i'd rather have it in sectors
    my $disk = "/dev/$part"; 
    $disk =~ s/\d+$// unless $disk =~ /p\d+$/;
    my $sfdisk = `sfdisk -l -uS $disk | grep  $part`;
    my $size = (split ' ', $sfdisk)[3];
    return $size;
}

sub repartition {
    my ($part, $size) = @_;
    print "DEBUG: repartitioning $part to $size sectors\n";
    my $disk = "/dev/$part"; $disk =~ s/\d+$//;
    my $swap_used = `grep $disk /proc/swaps`;
    # -1 is priority
    my ($swap_dev, $swap_prio) = (split(' ', $swap_used))[0,-1]; 
    system("swapoff $swap_dev");
    
    my $sfdisk = `sfdisk -d $disk`;
    $sfdisk =~ s/($part : start=\s+\d+, size=\s*)\d+/$1$size/;
    
    open my $sfdisk_pipe, "|sfdisk $disk" or die "sfdisk: $!";
    print $sfdisk_pipe $sfdisk;
    close $sfdisk_pipe;
    system("swapon -p $swap_prio $swap_dev"); # restore
}

sub set_wce {
    my $self = shift;

    my @phys = $self->get_disks;
    s#^#/dev/# for @phys;
    my ($e) = grep(-x,"/usr/bin/sdparm","/sbin/sdparm");
    System("$e --set=WCE --save @phys");
}

1;
