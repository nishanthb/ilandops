#! /usr/local/bin/perl

use Net::Netmask;
use CGI;
use strict;
use Data::Dumper;

print "Content-type: text/plain\nPragma: no-cache\n\n";

$ENV{"PATH"} .= ":/sbin:/usr/sbin:/bin:/usr/bin";

print "MTU=1500\n";

exit 0;

#XXX:(yuting): 下面是根据整个大的集群拓扑环境判断 mtu 的逻辑. 目前我们没有
#XXX:(yuting): 达到这么精细化运维，大部分的 ethernet 的 mtu 我们可以1500 为
#XXX:(yuting): 常用值.

eval { 
    my %routes;
    foreach my $route (split(/\n/,`netstat -nr`)) {
     if ($route =~ /^[0-9]+/) {
       my($dest,$gate,$mask,$flags,$mss,$window,$irtt,$iface) = split(/\s+/,$route);
       my $key = $dest  . ":" . $mask;
       my $b = new Net::Netmask("$key") or die "Failed to convert netmask";
       $routes{$key}{"block"}=$b;
       $routes{$key}{"size"}=$b->size();
       $routes{$key}{"iface"}=$iface;
     }
    }
    my @routes = sort {  $routes{$a}{"size"} <=> $routes{$b}{"size"}   }  keys %routes;

    my $REMOTE_ADDR = $ENV{"REMOTE_ADDR"};
    #$REMOTE_ADDR ||= "66.196.71.144";
    unless (defined $REMOTE_ADDR) {
       die "REMOTE_ADDR not defined\n";
    }

    my $iface;
    my $ifconfig;
    foreach my $route (@routes) {
      $b = $routes{$route}{"block"};
      if ($b->match($REMOTE_ADDR)) {
         $iface = $routes{$route}{"iface"};
         last;
      }
    }
    die "Could not find a route for $REMOTE_ADDR" unless (defined $iface);
    $ifconfig = ifconfig($iface);
    if ($ifconfig =~ m/ MTU:(\d+) /) {
       print "MTU=$1\n";
       exit 0;
    } else {
       die "Could not find mtu on $iface inside $ifconfig\n";
    }

};
if ($@)  {
  if (-t STDIN && -t STDOUT) {
     die $@;
  } else { 
    print "MTU=1500\n";
    exit 0;
  }
}



sub ifconfig {
  my($iface) = @_;
  my $ifconfig = `ifconfig $iface 2>&1`;
  $ifconfig =~ s/\s+/ /g;
  return $ifconfig;
}
