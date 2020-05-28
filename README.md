# gdig -- perform a DNS lookup as if from a geo location

`gdig(1)` is a tool to perform a `dig(1)` lookup as if
you were coming from the given geographical location.

This is dependent on the authoritative NS servers for
the given record to support and honor the EDNS Client
Subnet extension; if not supported, the results should
be the same as if via `dig(1)` itself.

Please see the [manual
page](https://github.com/jschauma/gdig/blob/master/doc/gdig.1.txt)
for details.

## Requirements

`gdig(1)` is old-school.  You'll need to have Perl
and the following modules installed:

* Net::DNS

Furthermore, you need to have the
[gip(1)](https://github.com/jschauma/gip/) utility
installed.

## Installation

You can install `gdig(1)` by running `make install`.
The Makefile defaults to '/usr/local' as the prefix,
but you can change that, if you like:

```
$ make PREFIX=~ install
```

---
```
NAME
     gdig -- get a DNS response for the given geo location

SYNOPSIS
     gdig [-46Vhv] country query [dig-args]

DESCRIPTION
     The gdig tool lets you perform a dig(1) lookup as if you were coming from
     the given geographical location.  It does this by determining a suitable
     CIDR subnet via the gip(1) utility and then passing this via the EDNS
     Client Subnet option '+subnet' argument on to dig(1).  In order to
     increase the odds that the ECS is not ignored by any resolvers, gdig will
     query the authoritative name server for the given query directly.

OPTIONS
     The following options are supported by gdig:

     -4	 Only use IPv4 ECS cidrs.

     -6	 Only use IPv6 ECS cidrs.

     -V	 Print version number and exit.

     -h	 Display help and exit.

     -v	 Be verbose.  Can be specified multiple times.

ARGUMENTS
     The first required argument to gdig will be passed on to gip(1) to deter-
     mine the ECS CIDR to use.

     The second required argument is the domain name to look up and which will
     determine the authoritative nameserver to query.  This argument will be
     passed on to dig(1).

     Any additional arguments will be passed on to dig(1) as well, allowing
     the user to specify any other options, if desired.

DETAILS
     gdig takes as the first argument a country, which it will pass on to the
     gip(1) utility to determine a suitable CIDR subnet.  This subnet will
     then subsequently used as the EDNS Client Subnet option as passed to
     dig(1) for the full query provided as subsequent arguments.

     Note: if the special argument 'none' is supplied as the country, then
     gdig will disable ECS by setting it explicitly to '0.0.0.0/0'.

     The part where gdig provides additional meaningful help is in that it
     will attempt to identify the authoritative nameservers for the given
     lookup and query those nameservers directly.

     In the process, gdig will first resolve any CNAMEs and then begin identi-
     fying the responsible NS record from the left-most side of the name.

     For example, to determine what the IPv4 address would be that Wikipedia's
     NS servers would return if you queried them from Japan, you might try to
     execute the following commands:

	   host -t cname www.wikipedia.org
	   host -t ns dyna.wikimedia.org.
	   host -t ns wikimedia.org.
	   gip -c japan
	   dig +subnet=185.102.64.0/22 @ns1.wikimedia.org dyna.wikimedia.org

     gdig will perform roughly those steps.

EXAMPLES
     The most common usage would likely look as follows:

     To send a query for 'www.wikipedia.org' as if coming from Japan:

	   gdig japan www.wikipedia.org

     To send a query for IPv6 addresses for 'www.yahoo.com' as if coming from
     Germany:

	   gdig germany www.yahoo.com -t AAAA +short

     To send a query for A records of 'google.com' as if coming from the sa-
     east-1 region in AWS:

	   gdig sa-east-1 google.com -t A +short

EXIT STATUS
     The gdig utility exits 0 on success, and >0 if an error occurs.

SEE ALSO
     dig(1), gip(1)

     RFC7871

HISTORY
     gdig was originally written by Jan Schaumann <jschauma@netmeister.org> in
     May 2020.

BUGS
     Please file bugs and feature requests by emailing the author.
```
