#! /usr/local/bin/perl

 print "Content-type: text/ascii\nPragma: no-cache\n\n/tmp/.update touched\n";
 open(RELOAD,">/tmp/.update");
 close RELOAD;

 # Notify zircon as well, since central can't.
system "/home/seco/tools/bin/allmanateed.pl -r zircon ndccheck";

