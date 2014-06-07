package Seco::Jumpstart::GroupsCfg;

use strict;
use warnings 'all';
use constant GROUPS_CF => "/usr/local/jumpstart/conf/groups.cf";
use constant MORE_PXE_ENTRIES =>
  "/usr/local/jumpstart/templates/more-pxe-entries";
use constant JS => "/usr/local/jumpstart";

use Seco::AwesomeRange qw/expand_range/;
use Seco::Jumpstart::Group;
use Seco::Jumpstart::Settings;
use Seco::Jumpstart::JS_Utils
  qw/read_big_file read_file dns_reset_warnings dns_read_warnings/;

use base 'Seco::Jumpstart::BaseCfg';
use fields qw/output cfg drb/;

sub new {
    my ($class, %vals) = @_;
    my __PACKAGE__ $self = fields::new($class);

    $self->SUPER::new;
    $self->{output} = JS . "/out";
    $self->{cfg}    = undef;

    $self->log('info', 'Parsing conf/groups.cf (and friends.)');
    $self->load_config();
    return $self;
}

sub create_profiles {
    my __PACKAGE__ $self = shift;
    my $output_dir = $self->{'output'};
    mkdir "$output_dir/profiles" unless -d "$output_dir/profiles";
    $self->log('info', 'Creating profiles.');
    while (my ($label, $group) = each(%{ $self->{'cfg'} })) {
        $group->create_profile("$output_dir/profiles/$label");
    }
}

sub create_pxe_configs {
    my __PACKAGE__ $self = shift;
    my $output_dir = $self->{'output'} . "/tftpboot/pxelinux.cfg";
    $self->log('info', 'Creating pxe configs.');
    mkdir $self->{'output'} . "/tftpboot", 0777;
    mkdir $output_dir, 0777;
    open my $fh, ">$output_dir/configs" or die "$output_dir/configs: $!";
    print $fh "TIMEOUT 1000\n\n";

    while (my ($label, $group) = each(%{ $self->{'cfg'} })) {
        $group->pxe_entry($fh, $label);
    }

    print $fh scalar(read_file(MORE_PXE_ENTRIES));
    print $fh "\n# Automatically generated on " . localtime() . "\n";
}

sub gen_needed_ssh_keys {
    my __PACKAGE__ $self = shift;
    my ($doit)           = @_;
    my $output_dir       = $self->{'output'};
    my $msg = $doit ? "Generating" : "Verifying";
    my $changes = 0;

    while (my ($label, $group) = each(%{ $self->{'cfg'} })) {
        $self->log('debug', "$msg needed ssh keys for $label");
        $changes += $group->gen_needed_ssh_keys(JS . "/skh", $doit);
    }

    return $changes;
}

sub count_hosts {
    my __PACKAGE__ $self = shift;
    my $total_count = 0;
    while (my ($label, $group) = each(%{ $self->{'cfg'} })) {
        $total_count += $group->count;
    }
    return $total_count;
}

sub host_records_range {
    my __PACKAGE__ $self = shift;
    my $range = shift;
    dns_reset_warnings();
    my %groups = %{ $self->{'cfg'} };

    $self->log('info', "Creating host records for $range.");
    my @nodes = expand_range($range);
    for my $node (@nodes) {
        my $group_label = Seco::Jumpstart::Group->get_label($node);
        unless ($group_label) {
            if ($node =~ /^nyn/) {
                warn "WARN: Can't find group for $node\n";
                return;
            }
            else {
                die "ERROR: Can't find group for $node\n";
            }
        }
        my $group = $groups{$group_label};
        $group->create_host_record($node);
    }
}

sub create_host_records {
    dns_reset_warnings();
    my __PACKAGE__ $self = shift;
    my $total_hosts = $self->count_hosts;
    $self->log('info', "Creating host records.");
    my $output_dir = $self->{'output'};
    Seco::Jumpstart::HostRecord->get->create_my_table;
    my $current_count = 0;
    local $| = 1;

    while (my ($label, $group) = each(%{ $self->{'cfg'} })) {
        if ($label ne "TO-BE-DONE") {
            $group->create_host_records;
        }
        $current_count += $group->count;
        printf "\rHosts processed: %d/%d", $current_count, $total_hosts;
    }
    print "\rHosts processed: $total_hosts" . " " x 20 . "\n";
    Seco::Jumpstart::DB->get_dbh->commit;
    my $dns_errors = dns_read_warnings();
    $self->log('warn', "Missing from tinydns: $dns_errors") if $dns_errors;
}

sub load_config {
    my __PACKAGE__ $self = shift;

    my %groups_seen;
    my ($c_group, $c_settings, @c_range);
    my @lines        = read_big_file(GROUPS_CF);
    my $line_no      = 0;
    my $fatal_errors = 0;
  LINE: for (@lines) {
        $line_no++;
        s/#.*$//;
        s/\s+$//;
        next unless length($_);

        /^([-\w]+)$/ and do {

            # new group
            my $group_name = $1;

            if ($groups_seen{$group_name}) {
                $self->log("error",
                        "Duplicate Group "
                      . "($group_name: $groups_seen{$group_name}, $line_no) MUST FIX!!!"
                );
                $fatal_errors++;
            }
            $groups_seen{$group_name} = $line_no;

            if ($c_group) {
                $self->{'cfg'}{$c_group} = Seco::Jumpstart::Group->new(
                    'label'    => $c_group,
                    'settings' => $c_settings,
                    'range'    => join(',', @c_range)
                );
                $self->{'cfg'}{$c_group}->update;
            }
            $c_group    = $group_name;
            $c_settings = {};
            @c_range    = ();
            next LINE;
        };

        /\s+([-\w]+)\s*=\s*([-\|\/"=<>:\w,;\s.*]+)$/ and do {
            my ($key, $value) = ($1, $2);
            if (exists $c_settings->{$key}) {
                $self->log("warn",
                    "Duplicate settings in group $c_group: $key");
            }
            unless (Seco::Jumpstart::Settings->valid_setting($key)) {
                $self->log("warn", "Invalid setting '$key' in group $c_group");
            }
            $c_settings->{$key} = $value;
            next LINE;
        };

        /\s+INCLUDE\s+(.*)/ and do {
            push @c_range, $1;
            next LINE;
        };

        /\s+EXCLUDE\s+(.*)/ and do {
            push @c_range, "-($1)";
            next LINE;
        };

        $self->log('error',
            "groups.cf:$line_no:Syntax error in or near group $c_group:$_");

    }
    if ($c_group) {
        $self->{'cfg'}{$c_group} = Seco::Jumpstart::Group->new(
            'label'    => $c_group,
            'settings' => $c_settings,
            'range'    => join(',', @c_range)
        );
        $self->{'cfg'}{$c_group}->update;
    }

    exit 1 if $fatal_errors;
}

sub get_group {
    my __PACKAGE__ $self = shift;
    my $name = shift;
    return $self->{'cfg'}{$name};
}

1;
