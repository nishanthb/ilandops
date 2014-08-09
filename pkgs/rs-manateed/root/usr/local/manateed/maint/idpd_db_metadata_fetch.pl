#! /usr/local/bin/perl -w

# $Id$
use strict;
use warnings 'all';

use Fatal qw(opendir closedir open close readlink :void lstat readdir);

use URI::Escape;
use Time::Local;
use FindBin qw($Bin $Script);
use Getopt::Long qw(:config no_ignore_case bundling);


use constant VERSION => '0.7';

################################################################################
sub usage
{
    print "Usage: $Script [--db <path>] [--maxlen <bytes>] [--all]

      -d,--db <path>       use 'path' instead of /ec/Current-database
      -m,--maxlen <bytes>  limits the size of values returned.  See NOTE below.
      -n,--nologparse      limits output to data not obtained by parsing logs
      -a,--all             dumps all key/val pairs collected.  Default is to
                           only give a small subset suitable for putting into
                           rrds.
      -v,--version         print version and exit
      -x,--debug           print debug output
      -h,--help            print this usage and exit

NOTE: maxlen is to limit the length of each value of each of the keys returned
by this script - however, after the value has been trimmed to maxlen, it is
url-encoded which will often make the final length of the value larger than
maxlen.\n";

}

# a hash to filter out input to the minimum
my %DefaultOutput = map { $_,1 } qw(
                                    currentdb.time
                                    setlivedb.time
                                    setlivedblink.time
                                    copydblink.time
                                    copylog.dur
                                    dbinfo.echmg.source.count
                                    dbinfo.marshal.doc_rate
                                    dbinfo.marshal.docs_built
                                    dbinfo.max_docs.expected
                                    dbinfo.num_docs
                                    dbinfo.num_words
                                    dbinfo.source.time.avg
                                    dbinfo.source.time.max
                                    dbinfo.source.time.med
                                    dbinfo.source.time.min
                                    dbinfo.db.time
                                    dbinfo.idpd.tags.lastapplied
                                    dbinfo.tagtool.tags.lastapplied
                                    dbinfo.indextime.ave
                                    dbinfo.indextime.min
                                    dbinfo.indextime.max
                                    dbinfo.last_crawl_time.ave
                                    dbinfo.last_crawl_time.min
                                    dbinfo.last_crawl_time.max
                                    copylog.time.first
                                    copylog.time.last
                                   );

my %ToDump;
my @Warnings;
my @Errors;

# emergency cap: we won't calc statistics for db if there are more
# than this many sources for the db
my $MAX_SOURCES = 100;

my $DUMP_ALL = 0;
my $NOLOGPARSE;
my $DATABASE = '';
my $MAXLEN = 300;
my $DEBUG = 0;
parse_args();

if ($DEBUG) {
    print "DEBUG: \$DATABASE=$DATABASE; \$MAXLEN=$MAXLEN;";
    print " \$DUMP_ALL=$DUMP_ALL; \$DEBUG=$DEBUG;";
    print " \%DefaultOutput=" . (scalar keys %DefaultOutput) . "elements;\n";
}
run_scrape();


################################################################################
sub run_scrape
{
    my $ec = '/export/crawlspace';
    my $db = $DATABASE;
    if ($db eq '') {
        my $dblink = readlink("$ec/Current-database");
        if ($dblink =~ /^\//) {
            $db = File::Spec->rel2abs($dblink);
        } else {
            $db = File::Spec->rel2abs("$ec/$dblink");
        }
        print "DEBUG: readlink:true; db:$db;\n" if ($DEBUG);
    }

    $ToDump{'currentdb'} = $db;
    $ToDump{'currentdb.time'} = get_time_from_date($db);

    my $slfn = "$ec/Setlive-database"; # (s)et (l)ive db link (f)ile (n)ame
    if (-l $slfn) {
        my $sldb = "$ec/";
        $sldb .= readlink($slfn);
        $ToDump{'setlivedb'} = $sldb;
        $ToDump{'setlivedb.time'} = get_time_from_date($sldb);
	$ToDump{'setlivedblink.time'} = (lstat($slfn))[9]; # mtime
    } else {
        $ToDump{'setlivedb'} = 'NONE';
        $ToDump{'setlivedb.time'} = 0;
	$ToDump{'setlivedblink.time'} = 0;
    }

    my $cpfn = "$ec/Copy-database"; # (c)o(p)y db link (f)ile (n)ame
    if (-l $cpfn) {
        my $cpdb = "$ec/";
        $cpdb .= readlink($cpfn);
        $ToDump{'copydb'} = $cpdb;
        $ToDump{'copydb.time'} = get_time_from_date($cpdb);
	$ToDump{'copydblink.time'} = (lstat($cpfn))[9]; # mtime
    } else {
        $ToDump{'copydb'} = 'NONE';
        $ToDump{'copydb.time'} = 0;
	$ToDump{'copydblink.time'} = 0;
    }

    if ($db !~ /DummyDB/ && !$NOLOGPARSE) {
        scrape_dbinfo("$db");
        scrape_copy_logs();
    }

    if ($DUMP_ALL) {
        foreach my $key (sort keys %ToDump) {
            print "$key=$ToDump{$key}\n";
        }
    } else {
        foreach my $key (sort keys %ToDump) {
            print "$key=$ToDump{$key}\n" if (exists $DefaultOutput{$key});
        }
    }

    print "WARNING: $_\n" foreach (@Warnings);

    if ($#Errors < 0) {
        print "STATUS: OK\n";
    } else {
        print "ERROR: $_\n" foreach (@Errors);
        print "STATUS: ERROR\n";
    }

    print "DEBUG: success\n" if ($DEBUG);
    exit 0;
}


################################################################################
sub scrape_dbinfo
{
    my $db = shift || die 'scrape_dbinfo() requires one scalar arg';

    if (ref($db)) {
        die 'scrape_dbinfo() requires one scalar arg';
    } # else $db is a scalar

    my $src_cnt = 0;
    my @src_date;

    my $info_dir = "$db/database.info";

    opendir(DIR, $info_dir);
    while (local $_ = readdir(DIR)) {
        next if /^[.]/;
        my $fn = "$info_dir/$_";
        $ToDump{"dbinfo.$_"} = get_contents($fn) if -f $fn;
    }
    closedir(DIR);

    if (exists $ToDump{'dbinfo.echelon.dbname'}) {
        $ToDump{'dbinfo.db.time'} =
            get_time_from_date($ToDump{'dbinfo.echelon.dbname'});
    }

    my $sCntFn = 'echmg.source.count'; # source count file name
    if (exists $ToDump{"dbinfo.$sCntFn"}) {
        $src_cnt = $ToDump{"dbinfo.$sCntFn"};
    }

    my $warning;
    for (my $i = 0; $i < $src_cnt && $i < $MAX_SOURCES; $i++) {
        my $sFn = "echmg.source.$i"; # source file name
        if (!exists $ToDump{"dbinfo.$sFn"}) {
            $warning  = 'dbinfo: missing echmg source marker;';
            $warning .= " missingFile:$sFn;";
            $warning .= " echmg.source.count:$src_cnt;";
            print "DEBUG: Warning: $warning\n" if ($DEBUG);
            next;
        }
        $src_date[$i] = get_time_from_date($ToDump{"dbinfo.$sFn"});
    }
    push(@Warnings, $warning) if (defined $warning);

    if ($src_cnt > $MAX_SOURCES) {
        my $warning = 'dbinfo: too many sources;';
        $warning   .= " \$MAX_SOURCES:$MAX_SOURCES;";
        $warning   .= " echmg.source.count:$src_cnt;";
        push(@Warnings, $warning);
    } else {
        my ($min, $avg, $med, $max) = get_mamm_stats(1,\@src_date);
        $ToDump{'dbinfo.source.time.min'} = $min;
        $ToDump{'dbinfo.source.time.avg'} = $avg;
        $ToDump{'dbinfo.source.time.med'} = $med;
        $ToDump{'dbinfo.source.time.max'} = $max;
    }

}

################################################################################
# get the contents of the given file, uri encode it, and return it
sub get_contents
{
    my $fn = shift || die 'get_contents() requires one scalar arg';

    if (ref($fn)) {
        die 'get_contents() requires one scalar arg';
    } # else $fn is a scalar

    open(I,"$fn");
    my $buf = '';
    my $nread = sysread(I, $buf, $MAXLEN);
    chomp($buf);
    close(I);

    return uri_escape($buf);
}


################################################################################
sub get_time_from_date
{
    my $b = shift;

    if (!defined $b || ref($b)) {
        die 'get_time_from_date() requires one scalar arg';
    } # else $b is a scalar

    my %m=qw(Jan 0 Feb 1 Mar 2 Apr 3 May 4 Jun 5
             Jul 6 Aug 7 Sep 8 Oct 9 Nov 10 Dec 11);

    if ($b =~ m/(\d\d\d\d)(\d\d)(\d\d)_?(\d\d)(\d\d)(\d\d)/) {
        return timegm($6,$5,$4,$3,($2-1),$1);
    }
    elsif ($b =~ /([^ ]{3})\s+(\d+)\s+(\d\d):(\d\d)\:(\d\d)\s+(\d\d\d\d)/) {
        return timegm($5,$4,$3,$2,$m{"$1"},$6);
    }
    elsif ($b =~ /DummyDB/) {
        return 0;
    }
    else {
        die "got bad date string: $b";
    }
}


################################################################################
sub scrape_copy_logs
{
    my $ec = '/export/crawlspace';
    opendir(DIR,$ec);
    my @copy_logs = sort ( grep { /^copy\.out-/ && -f "$ec/$_" } readdir(DIR) );
    closedir(DIR);

    my $cl = pop(@copy_logs);
    if (!defined $cl) {
        $ToDump{'copylog.time.first'} = 'NOT_AVAILABLE';
        $ToDump{'copylog.time.last'} = 'NOT_AVAILABLE';
        $ToDump{'copylog.filename'} = 'NOT_AVAILABLE';
        $ToDump{'copylog.lastline'} = 'NOT_AVAILABLE';
        $ToDump{'copylog.dur'} = 'NOT_AVAILABLE';
        return;
    }

    open(I,"$ec/$cl");
    my $last_cmd = 'NONE';
    my $first_ts = 'NONE'; # first time stamp
    my $last_ts = 'NONE'; # last time stamp
    my $line_count;
    my $cur_line;
    my $prev_line;
    my %cmds;
    while (my $line = <I>) {
        $line_count++;
        chomp($line);
        $prev_line = $cur_line;
        $cur_line = $line;
        if ($line =~ /^CMD:\s+(.*)$/) {
            $last_cmd = $1;
        }
        if ($line =~ /^AT:\s/) {
            $last_ts = get_time_from_date($line);
            $first_ts = $last_ts if ($first_ts eq 'NONE');

            $cmds{"$last_cmd"} = $last_ts;
        }
        if ($line =~ /^(Error\s+rc=\S+\s+sig=\S+\s+core=\S+)\s+from\s+(.*)$/) {
            my $m = $1; # m == message
            my $c = $2; # c == cmd
            push(@Warnings, "copy.out log has error: $m from $c");

            if (!exists $cmds{$c} || $c ne $last_cmd) {
                my $o = ''; # o for output
                $o = 'unexpected copy.out parsing inconsitancy - please ';
                $o .= 'investigate at some point: cmd in error line is ';
                $o .= "is not last command seen; err_cmd:$c; ";
                $o .= "last_cmd:$last_cmd; run with -x for more info";
                push(@Warnings, $o);
                print $o if ($DEBUG);

                if ($DEBUG) {
                    $o = 'possible script error: copy.out log announces ';
                    $o .= "an error on this line: [$line] but the ";
                    $o .= 'cmd that failed is not the last command that we ';
                    $o .= "parsed from the log: [$last_cmd]; \$m=$m; ";
                    $o .= "\$c=$c; ";
                    $o .= "\$c_exists:" . ((exists $cmds{"$c"})?"true":"false");
                    print $o;
                }
            }
        }
    }
    close(I);

    if ($DEBUG) {
        print "DEBUG: \$prev_line:[$prev_line]\n";
        print "DEBUG: \$cur_line: [$cur_line]\n";
    }

    $ToDump{'copylog.filename'} = "$ec/$cl";
    $ToDump{'copylog.time.first'} = $first_ts;
    $ToDump{'copylog.time.last'} = $last_ts;
    $ToDump{'copylog.lines'} = $line_count;
    if ($first_ts ne 'NONE') {
        $ToDump{'copylog.dur'} = $last_ts - $first_ts;
    } else {
        $ToDump{'copylog.dur'} = 0;
    }

    if ($line_count > 0) {
        $ToDump{'copylog.lastline'} = uri_escape($cur_line);
        if ($cur_line =~ /^Error/i) {
            push(@Errors,
                 "ERROR: $ec/$cl shows unsuccessful echmg; $cur_line\n");
        }
    }

    if ($line_count > 1 &&
        $prev_line =~ /Setlive-database/ &&
        $cur_line =~ /^AT:/ )
    {
        $ToDump{'copylog.complete'} = 'true';
    } else {
        $ToDump{'copylog.complete'} = 'false';
    }
}


################################################################################
# perl -e '@s=qw(1 2 3 4); if ($#s % 2) { $lv=int($#s/2) ;
#          $med = ($s[$lv] + $s[$lv+1]) / 2; } else { $med = $s[int($#s/2)]; };
#          print "med= $med\n";'
# med= 2.5
#
# mamm: (M)in(A)vg(M)ed(M)ax
sub get_mamm_stats
{
    my $force_int = shift;
    my $arr = shift;
    my ($min,$avg,$med,$max);

    my @vals = grep {defined $_ && $_ =~ /^[\d\.]+$/} @{ $arr };

    if ($#vals < 0) {
        print "DEBUG: min:'0'  avg:'0'  med:'0'  max:'0'\n" if ($DEBUG);
        return (0,0,0,0);
    }

    my @s = sort { $a <=> $b } @vals;

    $min = $s[0];
    $max = $s[$#s];

    if ($#s % 2) {
        my $lv = int($#s/2);
        $med = ($s[$lv] + $s[$lv+1]) / 2;
    } else {
        $med = $s[int($#s/2)];
    }

    my $tot = 0;
    foreach my $v (@s) {
        $tot += ($v - $min);
    }
    $avg = ( $tot / ($#s+1) ) + $min;

    if ($force_int) {
        $min = int($min);
        $avg = int($avg);
        $med = int($med);
        $max = int($max);
    }

    print "DEBUG: min:'$min'  avg:'$avg'  med:'$med'  max:'$max'\n" if ($DEBUG);

    return ($min,$avg,$med,$max);
}


################################################################################
sub parse_args
{
    my $help = 0;
    my $version = 0;

    GetOptions('all|a'        => \$DUMP_ALL,
               'nologparse|n' => \$NOLOGPARSE,
               'db|d=s'       => \$DATABASE,
               'maxlen|m=i'   => \$MAXLEN,
               'version|v'    => \$version,
               'help|h'       => \$help,
               'debug|x+'     => \$DEBUG)
        or die usage();

    if ($help) {
        usage();
        exit 0;
    }
    if ($version) {
        print "$Script version " . VERSION . "\n";
        exit 0;
    }

    return 0;
}
