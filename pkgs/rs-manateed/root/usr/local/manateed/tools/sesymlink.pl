#!/usr/local/bin/perl -w -T
#
use strict;
use Getopt::Long;
use Pod::Usage;
use File::stat;

#use Data::Dumper;

$ENV{PATH} = "/bin:/usr/bin:/sbin:/usr/sbin";

my $maindir = "/export/crawlspace";
my $searchdir = "$maindir/searcher";
my $crawlerdir = "$maindir/crawler";
my $permdir = "/perm";

my %links = (
    release => { 
        dir => $searchdir, name => "Release", 
        val => undef, check => \&checkRelease },
    config => {
        dir => $searchdir, name => "clusterConfig",
        val => undef, check => \&checkConfig },
    myrinet => {
        dir => $searchdir, name => "myrinet",
        val => undef, check => \&checkMyrinet },
    database => {
        dir => $maindir, name => "Current-database", 
        val => undef, check => \&checkDatabase },
    election => {
        dir => $searchdir, name => "Election", 
        val => undef, check => \&checkElection },
    libmlr => {
        dir => $searchdir, name => "libmlr", 
        val => undef, check => \&checkLibMlr },
    libyell => {
        dir => $searchdir, name => "libyell", 
        val => undef, check => \&checkLibYell },
    libspeller => {
        dir => $searchdir, name => "libspeller", 
        val => undef, check => \&checkLibSpeller },
    crawler => {
        dir => $crawlerdir, name => undef, 
        val => undef, check => \&checkGeneric },
    perm => {
        dir => $permdir, name => undef, 
        val => undef, check => \&checkGeneric }
);

my @args_to_getopt;
push @args_to_getopt, "$_=s", \$links{$_}->{val} for keys %links;
my $wants_help;
GetOptions(@args_to_getopt, help => \$wants_help) or pod2usage(2);
pod2usage(-verbose => 2) if $wants_help;;
# Display usage message if no options are passed
pod2usage(2) unless grep {defined} map { $links{$_}->{val} } keys %links;

#print Dumper(\%links);

# check links
while (my ($link, $linkdef) = each %links) {

	my $linkvalue;
	if ( ($link eq "crawler") || ($link eq "perm" )) {
		next unless $linkdef->{val} =~ m/,/ ;
		($linkdef->{name}, $linkvalue) = split(",", $linkdef->{val});
	}
	else {
    	$linkvalue = $linkdef->{val};
	}
    next unless $linkvalue;
    die "ERROR: Invalid link $linkvalue\n" unless $linkvalue &&
        $linkvalue !~ m{\.\.|/};
    
    # invoke the check sub if defined in the right directory
    chdir $linkdef->{dir} or die "ERROR: $link -> $linkdef->{dir}: $!\n";
    my $checksub = $linkdef->{check};
    $checksub->($linkvalue) if defined $checksub;
    setlink($linkdef->{name}, $linkvalue);
}

sub setlink {
    my ($name, $target) = @_;
    my $current = readlink($name);
    warn "WARNING: Current link for $target: $!\n" unless $current;
    if (defined $current) {
        unlink $name or die "ERROR: unlinking $name: $!\n";
    }
    symlink $target => $name or die "ERROR: symlinking $target => $name: $!";
    my $real = readlink $name or die "ERROR: readlink $name: $!\n";
    die "ERROR: $name => $real, instead of $target" unless $real eq $target;
    print "SUCCESS: changing $name -> $target\n";
}

sub checkRelease {
    my $target = shift;
    # we need to check that ./bin/idpd exists and is mode 04111
    # or that ./bin/proxy exists
    my $st;
    $st = stat($target) or die "ERROR: No $target: $!\n";
    my $idpd = "$target/bin/idpd";
    if (-x $idpd) {
#	my $platform = `file $idpd`;
#	die "ERROR: Bad platform" unless ($platform =~ m/intel/i);
        $st = stat($idpd) or die "ERROR: $idpd: $!\n";
        return if ($st->mode & 04111) == 04111;
    }
    if (-x "$target/bin/proxy") {
#       my $platform = `file $target/bin/proxy`;
#       die "ERROR: Bad platform" unless ($platform =~ m/intel/i);
       return;
    }
    die "ERROR: release=$target does not look good: no idpd / proxy found\n";
}

sub checkConfig {
    my $target = shift;
    return if -e "$target/clusterAccess.tcl";
    die "ERROR: No $target/clusterAccess.tcl found\n";
}

sub checkMyrinet {
    my $target = shift;
    return if -e "$target/lam_config";
    die "ERROR: No $target/lam_config found.\n";
}

sub checkDatabase {
    my $target = shift;
    return if -e "$target/database.version";
    die "ERROR: No $target/database.version found.\n";
}
sub checkElection {
    my $target = shift;
    return if -e "$target/cdxcore.version";
    die "ERROR: No $target/cdxcore.version found\n";
}

sub checkLibMlr {
    my $target = shift;
    return if -e "$target/lib/libmlr.so";
    die "ERROR: No $target/lib/libmlr.so found\n";
}

sub checkLibYell {
    my $target = shift;
    return if -e "$target/lib/libyell.so";
    die "ERROR: No $target/lib/libyell.so found\n";
}

sub checkLibSpeller {
    my $target = shift;
    return if -e "$target/lib/libspeller.so";
    die "ERROR: No $target/lib/libspeller.so found\n";
}

sub checkGeneric {
    my $target = shift;
    return if -e "$target";
    die "ERROR: $target does not exist.\n";
}

__END__

=head1 NAME

sesymlink.pl - manage symlinks for the search engine

=head1 SYNOPSIS

sesymlink [options]

 Options:
    --release=<newlink>
    --config=<newlink>
    --myrinet=<newlink>
    --database=<newlink>
    --election=<newlink>
    --help

=cut
