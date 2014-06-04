package Seco::Slogan;

our @slogans = <DATA>;
chomp @slogans;

sub new {
    return bless {}, shift;
}

sub random {
    return $slogans[rand int @slogans];
}

sub all {
    return @slogans;
}

__DATA__
SiteOpts: Size Does Matter!
Dirty Deeds, Done DIRT Cheap!
We make Yahoo! up
Opssss! we make it again
We make YoUP!
SiteOps Does It In The Data Center
StieOps: When it absolutely has to be up overnight!
SiteOps:  We go all night!
SiteOpts: Size Does Matter!
You want it done by WHEN?!
Ops:  345 Million Served.
Ops: Sleep is for the weak.
sure... we can do that.
Ops: The impossible?  Sure... we can do that.
Yahoo! Operations: "Your 24x7 Engine" ;-)
Yahoo! Operations "Always Available"
Yahoo! Operations >  On Time, On Target.
We make Network or Communication possible.
Is where the battle will be won
Around the clock!, Around the world!, 24 by 7 non-stop!
Ops: Keeping the wheels turning
Ops: All your datacentres are belong to us.
Y! Operations: The framework of the Internet.
Y! Operations We make the Internet work!
Y! Operations Because the Internet belong to us
Semper Praesto
Get Connected!
Network, service, data center
