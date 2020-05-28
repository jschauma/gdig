#! /usr/local/bin/perl -Tw
#
# This tool lets you perform a dig(1) lookup as if you
# were coming from the given geographical location.
#
# This code is beerware:
#
# Originally written by Jan Schaumann
# <jschauma@netmeister.org> in April 2020.
#
# As long as you retain this notice you can
# do whatever you want with this code.  If we
# meet some day, and you think this code is
# worth it, you can buy me a beer in return.

use 5.008;

use strict;
use File::Basename;
use Getopt::Long qw(:config posix_default);
use Net::DNS;

Getopt::Long::Configure("bundling");

# We untaint the whole path, because we do allow the
# user to change it to point to a curl(1) of their
# preference.
my $safepath = $ENV{PATH};
if ($safepath =~ m/(.*)/) {
	$ENV{PATH} = $1;
}

delete($ENV{CDPATH});
delete($ENV{ENV});

###
### Constants
###

use constant EXIT_FAILURE => 1;
use constant EXIT_SUCCESS => 0;

use constant VERSION => 1.0;

###
### Globals
###

my %OPTS;
my $PROGNAME = basename($0);
my $RETVAL = 0;

my @AUTHS;
my $ECS;

###
### Subroutines
###

sub error($;$) {
	my ($msg, $err) = @_;

	print STDERR "$PROGNAME: $msg\n";
	$RETVAL++;

	if ($err) {
		exit($err);
		# NOTREACHED
	}
}

sub findNS() {
	my $record = $OPTS{'record'};

	verbose("Looking up authoritative NS for '$record'...");

	my $res = Net::DNS::Resolver->new;
	my $query = $res->search($record);
	if (!$query) {
		error("Unable to resolve '$record'.", EXIT_FAILURE);
		# NOTREACHED
	}

	my $lookup = $record;
	foreach my $rr ($query->answer) {
		if ($rr->type eq "CNAME") {
			$lookup = $rr->rdstring;
		}
	}

	if ($lookup =~ m/^([0-9a-z\._-]+)$/i) {
		$OPTS{'lookup'} = $1;
	} else {
		error("Enexpectedly formatted record '$lookup'.", EXIT_FAILURE);
		# NOTREACHED
	}

	while (!scalar(@AUTHS)) {
		verbose("Looking up NS for '$lookup'...", 2);
		$query = $res->query($lookup, 'NS');
		if (!$query) {
			my @labels = split(/\./, $lookup);
			# ok, we should use the suffix list here, but for now we're lazy
			if (scalar(@labels) <= 2) {
				error("Unable to find any NS records all the way up to '$lookup'.", EXIT_FAILURE);
				# NOTREACHED
			}
			$lookup =~ s/^.*?\.//;
			next;
		}
		foreach my $rr ($query->answer) {
			if ($rr->rdstring =~ m/^([0-9a-z\._-]+)$/i) {
				push(@AUTHS, $1);
			} else {
				error("Ignoring unexpected result '" . $rr->rdstring . "'.");
			}
		}
	}

	verbose("Responsible auths: " . join(", ", @AUTHS));
}

sub getECSFromGip() {
	# $OPTS were untainted in init()
	my $country = $OPTS{'country'};

	if ($country eq "none") {
		$ECS = "0.0.0.0/0";
		return;
	}

	verbose("Getting an ECS for '" . $OPTS{'country'} . "' from gip(1)...");

	my @cmd = ( "gip", "-c" );
	if ($OPTS{'4'}) {
		push(@cmd, "-4");
	}
	if ($OPTS{'6'}) {
		push(@cmd, "-6");
	}
	push(@cmd, $country);

	verbose("Running '" . join(" ", @cmd) . "'...", 2);

	my $pipe;
	open($pipe, "-|", @cmd) or die "Unable to open pipe to '" . join(" ", @cmd) . "': $!";
	my @cidrs;
	while (my $ecs = <$pipe>) {
		chomp($ecs);
		push(@cidrs, $ecs);
	}
	close($pipe);

	if (!scalar(@cidrs)) {
		error("Unable to determine a suitable ECS for '$country'.", EXIT_FAILURE);
		# NOTREACHED
	}

	$ECS = $cidrs[rand(@cidrs)];

	if ($ECS =~ m/^([0-9a-f.:\/]+)$/i) {
		$ECS = $1;
	} else {
		error("Got an unexpectedly formatted ECS CIDR from gip(1): '$ECS'.", EXIT_FAILURE);
		# NOTREACHED
	}

	verbose("Using ECS '$ECS'...");
}

sub init() {
	if (!scalar(@ARGV)) {
		error("I have nothing to do.  Try -h.", EXIT_FAILURE);
		# NOTREACHED
	}

	my $ok = GetOptions(
			"ipv4|4"	=> sub { $OPTS{'4'} = 1; $OPTS{'6'} = 0; },
			"ipv6|6"	=> sub { $OPTS{'6'} = 1; $OPTS{'4'} = 0; },
			"help|h"	=> \$OPTS{'h'},
			"verbose|v+"	=> sub { $OPTS{'v'}++; },
			"version|V"	=> \$OPTS{'V'},
		);

	if ($OPTS{'h'} || !$ok) {
		usage($ok);
		exit(!$ok);
		# NOTREACHED
	}

	if ($OPTS{'V'}) {
		print "$PROGNAME " . VERSION . "\n";
		exit(EXIT_SUCCESS);
		# NOTREACHED
	}

	if (scalar(@ARGV) < 2) {
		usage(1);
		exit(EXIT_FAILURE);
		# NOTREACHED
	}

	$OPTS{'country'} = shift(@ARGV);
	if ($OPTS{'country'} =~ m/^([a-z0-9-]+)$/i) {
		$OPTS{'country'} = $1;
	} else {
		error("Invalid location argument '" . $OPTS{'country'} . "'.", EXIT_FAILURE);
		# NOTREACHED
	}

	$OPTS{'record'} = shift(@ARGV);

	if ($OPTS{'record'} =~ m/^([a-z0-9.:_-]+)$/i) {
		$OPTS{'record'} = $1;
	} else {
		error("Invalid record argument '" . $OPTS{'record'} . "'.", EXIT_FAILURE);
		# NOTREACHED
	}

	$OPTS{'dig-args'} = \@ARGV;

	my $gip = `which gip 2>/dev/null`;
	if (!$gip) {
		error("gip(1) not found in your PATH.\nPlease install from: https://github.com/jschauma/gip", EXIT_FAILURE);
		# NOTREACHED
	}
}

sub runDig() {

	# $ECS was untainted when it was produced
	# $OPTS were untainted in init

	my $lookup = $OPTS{'lookup'};
	my $ns = $AUTHS[rand(@AUTHS)];

	# dig-args can be used safely since we don't shell out
	my @digArgs;
	foreach my $arg (@{$OPTS{'dig-args'}}) {
		if ($arg =~ m/(.*)/) {
			push(@digArgs, $1);
		}
	}

	my @cmd = ( "dig", "+subnet=$ECS", "@" . $ns, $OPTS{'lookup'}, @digArgs );

	verbose("Running '" . join(" ", @cmd) . "'...");
	exec { $cmd[0] } @cmd;
}

sub usage($) {
	my ($err) = @_;

	my $FH = $err ? \*STDERR : \*STDOUT;

	print $FH <<EOH
Usage: $PROGNAME [-Vhv] country query
	-V  print version number and exit
	-h  print this help and exit
	-v  be verbose
EOH
	;
}

sub verbose($;$) {
	my ($msg, $level) = @_;
	my $char = "=";

	return unless $OPTS{'v'};

	$char .= "=" x ($level ? ($level - 1) : 0 );

	if (!$level || ($level <= $OPTS{'v'})) {
		print STDERR "$char> $msg\n";
	}
}


###
### Main
###

init();
findNS();
getECSFromGip();
runDig();

exit($RETVAL);
