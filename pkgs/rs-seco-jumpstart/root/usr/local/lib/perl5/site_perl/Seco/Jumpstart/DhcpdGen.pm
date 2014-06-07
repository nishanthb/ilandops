package Seco::Jumpstart::DhcpdGen;

use strict;
use warnings;
use Net::Netmask;
use constant NET_DIR        => "/usr/local/jumpstart/files/net";
use constant DHCPD_TEMPLATE => "/usr/local/jumpstart/templates/dhcpdconfig";
use constant JS             => "/usr/local/jumpstart";

use Seco::AwesomeRange qw/:all/;
use Seco::Jumpstart::HostRecord;
use Seco::Jumpstart::JS_Utils qw/fqdn read_file/;
use YAML::Syck qw();

use base qw(Seco::Jumpstart::BaseCfg);
use fields qw(ignore group_cfg dir template outdir group_db admins netblocks);

my %WARNINGS;
my %mac_errors;

END {
    my $label = __FILE__;
    $label =~ s#.*/##;
    foreach my $key (sort keys %WARNINGS) {
        my $r = compress_range(keys %{ $WARNINGS{$key} });
        print "WARNINGS: $label: $key: range $r\n";
    }
}

sub new {
    my ($class, $gc, $dirname) = @_;
    $dirname ||= NET_DIR;
    my __PACKAGE__ $self = fields::new($class);
    $self->SUPER::new;
    $self->{dir}    = $dirname;
    $self->{outdir} = JS . "/out/dhcpd";
    mkdir $self->{outdir} unless -d $self->{outdir};
    $self->{template}  = read_file(DHCPD_TEMPLATE);
    $self->{admins}    = YAML::Syck::LoadFile(JS . "/conf/admins.cf");
    $self->{netblocks} = $self->preprocess_netblocks;
    $self->{group_cfg} = $gc;
    my $ignore = $self->parse_ignore_file;
    $self->{ignore} = $ignore;
    return $self;
}

sub parse_ignore_file {
    my %res;
    open my $fh, JS . "/conf/IGNORE" or return;
    while (<$fh>) {
        my ($msg, $range) = /^(.*?): (.*)/;
        my @range = expand_range($range);
        for my $node (@range) {
            $res{$node} = $msg;
        }
    }
    close $fh;
    return \%res;
}

sub preprocess_netblocks {

    # pre-generate a hash with key = 20.20.20.0/26 and values
    # for subnet-mask/broadcast-address/routers
    my __PACKAGE__ $self = shift;
    my %netblocks;
    my %adm = %{ $self->{admins} };
    for my $admin (keys %adm) {
        my %adm_info = %{ $adm{$admin} };
        my $n_gw     = $adm_info{gateways};
        my $networks = $adm_info{networks};
        for my $net (@$networks) {
            next if exists $netblocks{$net};
            my $n = Net::Netmask->new($net);
            my @gws;
            for (my $i = 1 ; $i <= $n_gw ; $i++) {
                push @gws, $n->nth($i);
            }

            my $netmask   = $n->mask;
            my $broadcast = $n->broadcast;
            my $base      = $n->base;
            my @boothosts = expand_range("boot_v(q($net))");

            $netblocks{$net} = {
                gateways  => \@gws,
                netmask   => $netmask,
                broadcast => $broadcast,
                base      => $base,
                boothosts => \@boothosts,
            };
        }
    }
    return \%netblocks;
}

sub generate {
    local $_;
    my __PACKAGE__ $self = shift;
    my $gc               = $self->{group_cfg};
    my ($admin)          = @_;
    print "DEBUG: generating configs for $admin\n";
    my $dir         = $self->{dir};
    my $outdir      = $self->{outdir};
    my $extra_dhcpd = "";
    my $ignore      = $self->{ignore};
    if (-e "$dir/$admin.dhcpd") {
        $extra_dhcpd = read_file("$dir/$admin.dhcpd");
    }

    my %admininfo = %{ ${ $self->{admins} }{$admin} };
    my %netblocks = %{ $self->{netblocks} };
    my @networks  = @{ $admininfo{'networks'} };
    my $bh_vlan   = (expand_range("vlan($admin)"))[0];
    push @networks, $bh_vlan if $bh_vlan;
    @networks = uniq(\@networks);

    open my $out, ">$outdir/$admin" or do {
        $self->log("error", "$outdir/$admin: $!");
        return;
    };
    print $out "# Automatically generated on " . scalar localtime() . "\n";
    print $out $self->{template};
    print $out "\n";

    for my $net (@networks) {
        my $net_info = $netblocks{$net};
        die "NO NET INFO FOR $net\n" unless $net_info;
        my $broadcast = $net_info->{broadcast};
        my $network   = $net_info->{base};
        my $netmask   = $net_info->{netmask};
        print $out <<"EOT";
subnet $network netmask $netmask {
    option broadcast-address $broadcast ;
}
EOT
    }
    print $out $extra_dhcpd;
    my $vlan_range = join(",", map { "q($_)" } @networks);
    my @nodes = expand_range("hosts_v($vlan_range) & \@ALL");
    die "FATAL: no nodes for $admin\n" unless @nodes;
    for my $node (@nodes) {
        if ($ignore->{$node}) {
            my $ignore_msg = $ignore->{$node};
            print $out "# IGNORING: $node = $ignore_msg\n";
            next;
        }
        my $hr    = Seco::Jumpstart::HostRecord->get($node);
        my $group = $hr->label;
        if (!defined $group) {
            $WARNINGS{"NOGROUP"}{$node}++
              unless $node =~ /^nyn/;
            print $out "# WARNING: host $node group not defined in jumpstart\n";
            next;
        }

        next if $group eq 'TO-BE-DONE';
        my $js_group = $gc->get_group($group);
        unless ($js_group) {
            print "ERROR: can't get_group($group) for $node\n";
            next;
        }
        my $group_settings = $js_group->settings;
        my $ip             = $hr->ip;
        next unless $ip;
        my $macaddr = $hr->macaddr;
        unless ($macaddr) {
            $WARNINGS{"NOMACADDR"}{$node}++
              unless $node =~ /^nyn/;
            print $out "# WARNING: host $node ip $ip macaddr missing\n";
            next;
        }
        unless (
            $macaddr =~ /\A ([0-9a-f]{1,2} # one or two digits
            :                                  # separator
            ){5}                               # 5 times
            [0-9a-f]{1,2}                      # final byte
            \z/msxi
          )
        {
            unless ($mac_errors{$node}) {
                $self->log("error", "Wrong mac address: $node $macaddr");
                $mac_errors{$node}++;
            }
            next;
        }

        my $domain_name         = $group_settings->get('domain-name');
        my $domain_name_servers = $group_settings->get('domain-name-servers');
        my $domain_text         = "";
        my $net                 = (expand_range("vlan($node)"))[0];
        my %net_info            = %{ $netblocks{$net} };
        my @gws                 = @{ $net_info{gateways} };
        my $sm                  = $net_info{netmask};
        my $bc                  = $net_info{broadcast};
        my $i                   = $ip;
        $i =~ s/.*\.//;
        my $gw   = $gws[ $i % @gws ];
        my $fqdn = fqdn($node);

        my $bh_group = $group_settings->get('tftp-server');
        my (@bh, $bh);
        if ($bh_group eq "DEFAULT") {
            @bh = @{ $net_info{boothosts} };
        }
        else {
            @bh = expand_range($bh_group);
        }
        $bh = $bh[ $i % @bh ];

        my $pxelinux = $group_settings->get('pxelinux');
        $pxelinux =~ s/__IP__/$ip/g;

        my $next_server = "\n    next-server $bh;";
        if ($bh eq $node) {
            $next_server = "";
        }

        my $root_path = $group_settings->get('root-path');
        if ($root_path =~ /\//) {
            $domain_text .= qq(\n    option root-path $root_path;);
        }

        if ($domain_name ne "*") {
            $domain_text = qq(\n    option domain-name "$domain_name";);
        }
        if ($domain_name_servers ne "*") {
            $domain_text .=
              qq(\n    option domain-name-servers $domain_name_servers;);
        }

        print $out <<EOT;
host $node {$next_server
    hardware ethernet $macaddr;
    server-name "$fqdn";
    fixed-address $ip;$domain_text
    option routers $gw;
    option subnet-mask $sm;
    option broadcast-address $bc;
    filename "$pxelinux";
}

EOT
    }
    close $out;
}

sub generate_all {
    my __PACKAGE__ $self = shift;
    $self->generate($_) for keys %{ $self->{admins} };
}

sub uniq {
    my $aref = shift;
    my %u;
    @u{@$aref}++;
    return keys %u;
}

1;

