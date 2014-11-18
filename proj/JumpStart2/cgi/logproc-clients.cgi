#!/usr/local/bin/perl

printf("Content-type: text/plain\n\n");
if ( -x "/usr/local/bin/p4" ) {
    open( FILE,
        "/usr/local/bin/p4 print //depot/logproc/main/bin/LogConfig.pm.reference |"
    );
} else {
    open( FILE, "/home/seco/tools/lib/LogConfig.pm" )
      || die("unable to open /home/seco/tools/lib/LogConfig.pm : $!");
}
while (<FILE>) {
    last if (/\*facade_redirect =/);
}
while (<FILE>) {
    last if (/\*facade_logdir/);
    if (/\s+(\d+),\s+["'](\S+)["'],\s+(\d{8}),\s+["'](\S+)["'],/) {
        printf( "%s=%s\n", $1, $4 );
    }
} ## end while (<FILE>)
close FILE;
