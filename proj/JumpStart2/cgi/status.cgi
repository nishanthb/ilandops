#! /usr/local/bin/perl

use lib '/home/seco/tools/hourly/3ware';
use lib "/home/seco/tools/lib";

 use CGI;
 use Socket;
 use Seco; 
 use AllManateed;
 use ThreeWare;

 $q = new CGI;
 select(STDERR); $|=1;
 select(STDOUT); $|=1;

 print "Content-type: text/html\nPragma: no-cache\n\n";

 $JSDIR = "/JumpStart";
 @files = glob("$JSDIR/hosts/*");

 $cmd_fping = "ls -1 $JSDIR/hosts/ | /usr/bin/fping -i 10 -a 2>/dev/null |";
 open(cmd_PIPE,$cmd_fping);   # Start fping running, while we do other stuff

 foreach $file (@files) {
   $host = $file; $host =~ s#.*/##;
   open(FILE,"<$file") || next;
   $hosts{$host}{"hostname"}=$host;
   $hosts{$host}{"pingable"}="no";
   while(<FILE>) {
     chomp;
     next if (/^#/);
     ($a,$b) = split(/\s+/,$_,2);
     $hosts{$host}{$a}=$b;
   }
 }

 # This is one block of ugly code!
 foreach $host (keys %hosts) {
   $ip = $hosts{$host}{"ip"};
   unless (defined $ip) {
      print "WARNING: No ip defined for host file $host<br>\n";
      next;
   }
   @possibles=  ();
   foreach $length (8,7,6,5,4,3,2,1) {
     push(@possibles,
        "/tftpboot/pxelinux.cfg/" . 
        substr(sprintf("%08X",unpack("N",inet_aton($ip))),0,$length));
   }
   push(@possibles,"/tftpboot/pxelinux.cfg/default");
   ($possible) = grep(-f,@possibles);
   $possible  ||= "/tftpboot/pxelinux.cfg/default";
   unless(open(POSSIBLE,"<$possible")) {
     print "WARNING: Unable to open < $possible<br>\n";
     next;
   }
   $label = "missing";
   while(<POSSIBLE>) {
      chomp;
      if (/^DEFAULT\s+(\S+)$/) {
          $label = $1; 
          $hosts{$host}{"LABEL"} = $label;
      }
      if (/LABEL $label$/) {
         while(<POSSIBLE>) {
	   chomp;
           last if (/^\s*$/);
           if (/\s*KERNEL\s*(\S+)$/) {
             $hosts{$host}{"KERNEL"} = $1;
           }
           if (/\s*APPEND\s+(\S.*)$/) {
             $append = $1;
             $hosts{$host}{"APPEND"} = $1;
           }
         }
      }
   }
   close(POSSIBLE);
 }

  ######################################################
  # Check 3ware                                        #
  ######################################################

my $threeWare = new ThreeWare(
    verbose => 0,
    timeout => 3,
#    max_hosts => 180,
    quiet => $quiet);

 $range = CompressRange(%hosts);
 print "checking  3ware range $range\n";
 my %res = $threeWare->check($range);
 foreach $host (keys %res) {
   $hosts{$host}{"3ware"} = $res{$host};
 }

  ######################################################
  # Check uname via manateed                           #
  ######################################################

 $am = new AllManateed;
 $am->port(12345);
 $am->tcp_timeout(3);
 $am->read_timeout(3);
 $am->maxflight(100);
 
 my %res = $am->command($range,"uname -r");
 foreach $host (keys %res) {
   $hosts{$host}{"uname_r"} = shift @{$res{$host}} ;
 }



  ######################################################
  # Check fping pipe                                   #
  ######################################################

 # We previously opened this pipe.  Now lets read it.
 while(<cmd_PIPE>) {
   chomp;
   $hosts{$_}{"pingable"}="yes";
  
 }
 close cmd_PIPE;


# Later: Add "sort by" code here 
@hosts = sort keys %hosts;

@show = qw(
 hostname pingable ip macaddr nextboot force disks   
 uname_r
 LABEL KERNEL APPEND
 3ware
);

print "<table border=0>\n <tr>\n";
foreach (@show) {
  print "  <td bgcolor=black><b><font color=white size=-1>$_</font></b></td>\n";
}
print " </tr>\n";

@colors = qw(#ffffffff #ffeeeeee #dddddd #ddcccccc);

foreach $host (@hosts) {
  print " <tr>\n";
  @c = ();
 
  # Rotate two colors left and capture
  push(@c, shift @colors);
  push(@c, shift @colors);
  push(@colors,@c);

  foreach $show (@show) {
    $c = shift @c;  push(@c,$c);
    print "  <td bgcolor=$c><font size=-1>$hosts{$host}{$show}</font></td>\n";
  }
  print " </tr>\n";
}

print "</table>\n";

sub panic {
  print @_;
  die;
}
