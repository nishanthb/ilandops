#! /usr/local/bin/perl5 -T

use CGI;

$ENV{"PATH"} = "/bin:/usr/bin:/usr/local/bin";

$q = new CGI;

print "Content-type: text/html\nPragma: no-cache\n\n";

$url = $q->param("url");
if ($q->param("Submit")) {
  trysubmit();
}


print <<EOF ;
<h1>Signup Tool</h1>
You came from <a href="$url">$url</a>.  If you entered your password
incorrectly, click <a href="$url">here</a> to try again.<p>

Web servers operated by the Inktomi search operations groups are currently
password protected.  In the future we will link authentication into Yahoo's
single signon system.  Until then, we're doing things the old fashioned way.
<p>
If you would like access to these web serveres, we'll need to know a bit
more about why; you'll need a valid business reason to access the data.
This is because not all Yahoo employees are supposed to see Inktomi OEM
data, to preserve the privacy of our customers.  This <b>is</b> a sensitive
issue with our customers!.
<p>
EOF

print "<form method=\"post\" action=\"signup.cgi\">";
print $q->hidden("url");
print "<table>";
print "<tr><th colspan=2>Signup Form</th></tr>";

$warning = $warning{"name"} || "";
print "<tr><td>Your name</td>";
   print "<td>" . $q->textfield('name') . "</td><td>$warning<td></tr>";
$warning = $warning{"email"} || "";
print "<tr><td>Your email address</td>";
   print "<td>" . $q->textfield('email') . "</td><td>$warning</td></tr>";
$warning = $warning{"id"} || "";
print "<tr><td>Your requested ID</td>";
   print "<td>" . $q->textfield('id') . "</td><td>$warning</td></tr>";
$warning = $warning{"pass1"} || "";

print "<tr><td>Your requested password</td>";
   print "<td>" . $q->password_field('pass1') . "</td><td>$warning</td></tr>";
$warning = $warning{"pass2"} || "";
print "<tr><td>Your requested password (again)</td>";
   print "<td>" . $q->password_field('pass2') . "</td><td>$warning</td></tr>";

print "<tr><td colspan=2>
Why are you requesting access? Please document who <br>
you report to, and why you need access to this data.<br>
We will verify this with your manager.  We will also<br>
contact you to verify your request.<p>";
$warning = $warning{"comment"};
print "$warning<p>" if (length($warning));
print $q->textarea('comment','',10,50);
print "</td></tr>";
print "</table>";
print $q->submit("Submit");
print "</form>";



sub trysubmit {

 $validate{"email"} =  '[a-z0-9]+\@(inktomi.com|yahoo-inc.com)';
 $validate{"name"}  =  '[a-z0-9 -]+';
 $validate{"id"}  =  '[a-z0-9-]{1,8}';
 $validate{"pass1"} = '.{6,8}';
 $validate{"pass2"} = '.{6,8}';
 $validate{"comment"} = '.+';

 foreach $key (sort keys %validate) {
    $val = $q->param($key);
    $val =~ s/^\s+//;  $val =~ s/\s+$//;
    $how = $validate{$key};
    if ($val =~ m/^($how)$/mi) {
      $validated{$key}=$1;
    } else {
      $warning{$key} = "<font color=red><b>$key must match $how</b></font>";
    }
 }
 unless ($validated{"pass1"} eq $validated{"pass2"}) {
    $warning{"pass2"} = "<font color=red><b>Password does not match</b></font>";
 }
 if (defined $validated{"pass1"}) {
   ($testpass,$testreason) = testpassword($validated{"pass1"});
   unless ($testpass) {
      $warning{"pass1"} = "<font color=red><b>$testreason</b></font>";
   }
 }
 if (scalar %warning) {
   print "<h2><font color=red>Errors found</font></h2>Look for the errors in <font color=red>red</font> below.<hr>";
 }
 return if (scalar %warning);
 print "Confirmed! Lets do something now.<hr>";

 send_bug();
 exit();

}



sub testpassword {
 my($pw) = (@_);
 my($tempfile) = "/tmp/.signup.$$";
 open(PIPE,"|/JumpStart/cgi/cracklib-test.bin 2>&1 > $tempfile");
 print PIPE "$pw\n";
 close PIPE;
 if ($?) {
   $reason = `cat $tempfile`;
   unlink($tempfile);
   return(0,$reason);
 } else {
   return(1,"OK");
 }
}


sub send_bug {
  
$saltbase = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
srand;
$salt = substr($saltbase,int rand (length $saltbase),1) .
        substr($saltbase,int rand (length $saltbase),1) ;

$enc =  crypt($validated{"pass1"},$salt);

my $message = <<"EOF";
From: jumbobz\@inktomi.com
To: bug2jumbo\@inktomi.com
Subject: Web server request from $validated{name}
Cc: $validated{email}

Web server access request
Name: $validated{name}
Email: $validated{email}

Please add to the web access list the following line and repush:

$validated{id}:$enc:9999:9999:$validated{name}:/nonexistent:/dev/null
(Encrypted password has been libcrack validated)

Comment from user:
$validated{comment}


EOF


print "Congratulations!  Your request is being forwarded to the  job queue.<p><pre><code>$message</code></pre>";

open(SENDMAIL,"|/usr/sbin/sendmail -t");
print SENDMAIL $message;
close SENDMAIL;

print "</code></pre>";
print "<hr>Please allow up to 1 business day for this request to be processed.  You will be notified that a bug has been filed, and when the bug has been processed and closed.<p>";



}
