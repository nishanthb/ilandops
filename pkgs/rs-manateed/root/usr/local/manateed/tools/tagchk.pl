#! /usr/local/bin/perl5

use strict 'vars';
use vars qw(%bitcount %argv $size);
use Getopt::Long;

my $rl = readlink("/export/crawlspace/Current-database");
if ($rl =~ /dummy/i) {
  print "Not running for $rl\n";
  exit;
}

chdir "/export/crawlspace/Current-database/." || die "Could not chdir /export/crawlspace/Current-database/.";

my @enumcount = (qw(tagchk.field));
&report_doccount;

foreach (@enumcount) {&enumcount($_);}

sub enumcount {
  my($name) = @_;
  my($href,$sref) = &fetchfield("database.fields/$name");
  my(%count) = ();
  my($total)=0;
  my($tagchk)=0;

  if (${$href}{'width'}==8) {
    # Fast 
    my($string)=$$sref;
    my($count,$length)=(0,length($string));
    for($count=0;$count<$length;$count++) {
      $count{ord(substr($string,$count,1))}++;  
    }
  } else {
    # Slow
    my($aref) = &unpacker(${$href}{'width'},$sref);
    foreach (@$aref) {
      $count{$_}++;
    };
  }
  foreach (sort {$a <=> $b} keys %count) {
    next unless ($count{$_});
    my($key)=${$href}{'enum'}{$_} || $_;
#    print "$name-$key $count{$_}\n";
    $total += $count{$_};

#tagchk.field-0 975216
#tagchk.field-54 16570

    if ($key > 0 ) {
      if ($tagchk >0) {
        print "WARNING: Multiple tagchk values in this field file (changing tagchk from $tagchk to $key)\n";
      }
      $tagchk = $key;
    }
  }
  if ($total != $size) {
     print "WARNING:  Field file doesn't match length of database\n";
  }
  if ($tagchk == 0) {
     print "WARNING:  All tagchk values are 0\n";
  }
  print "tagchk=$tagchk\n";
}



sub fetchfield {
  my(%hash,@array)=();
  my($fieldfile) = @_;
  open(FILE,"+<$fieldfile")||die "failed to open +<$fieldfile : $!";
  my($x,$BUFFER)=();
  $x = read FILE,$BUFFER,-s $fieldfile;  

  # Read the header, then strip it
  my (@data) = unpack("A4A2A2A2A6NnnnnNNCC",$BUFFER);
  foreach (qw(identifier major minor patch padding dataoffset width type majordata minordata numberdata txtoffset)) {
   $hash{$_}=shift @data;
  }

  my $text = substr($BUFFER,38,$hash{'dataoffset'}-38);
  #print "text is:\n$text\n------------\n";
  my(@text) = split(/\n/o,$text);
  foreach (@text) {
    if (/^(\d+)=(.*)$/) {
       $hash{'enum'}{$1}=$2;
    }
  }
  substr($BUFFER,0,$hash{'dataoffset'})=();
  if ($hash{'type'} == 2) {   # Magic.
    $hash{'width'} = 'f';  
  }

   return(\%hash,\$BUFFER);
}

  ######################################################
  # unpacker                                           #
  # input: bitwidth (or "f" for floating)              #
  # input: reference to binary string                  #
  # output: reference to decoded array                 #
  ######################################################

sub unpacker {
  my($bits,$sref) = @_;
  my(@array)=();
  if ($bits eq "f") {@array = unpack("f*",$$sref);}
  elsif ($bits==1) {@array = split(//o,unpack("b*",$$sref));}
  elsif ($bits==8) {@array = unpack("C*",$$sref);}
  elsif ($bits==16) {@array = unpack("S*",$$sref);}
  elsif ($bits==32) {@array = unpack("I*",$$sref);}
  return \@array;  
}

sub getoptions {
  $argv{'d'} ||= "/export/crawlspace/Current-database";
}


sub report_doccount {
  $size = -s "database.docindex/big-00000000";
  $size = $size / 10;
#  print "doccount $size\n";
}

