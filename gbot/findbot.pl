#!/usr/bin/perl
use strict;
use warnings;
# use diagnostics;

# Object oriented, non-blocking IO
use IO::Socket::INET;
use IO::Select;

# Include script directory in include search path
# Removed by Perl 5.26 for security reasons, but we still need it.
use FindBin qw( $RealBin );
use lib $RealBin;

my $FIBS_SERVER_HOST = "fibs.com";
my $FIBS_SERVER_PORT = 4321;
our $LOCK_NAME;
our $LOCK_PASSWD;
our @BOT_NAMES = [];
our $BOT_PASSWD;

# use the next to change any defaults, also bot strentgh file
require "botlist.pl";

sub main() {
	my $gbot;
	# Connect to fibs.com.
	#
	our $lock_sock = &connect_to_botLock();

	if (not $lock_sock) {
		print "null socket\r\n";
	} else {
		print "open socket\r\n";
		foreach (@BOT_NAMES) {
			$gbot = find_idle_bot($_);
			last if (length($gbot));
		}
		$lock_sock->close() if $lock_sock;
		if (length($gbot)) {
			print "Found Offline bot! " . $gbot . "\r\n";
			open(FH, '>', "mybot.pl") or die $!;
			print FH '$BOTID = "' . $gbot . '";' . "\r\n";
			print FH '$BOTPASS = "' . $BOT_PASSWD . '";' . "\r\n";
			close(FH);
		}
	}
	exit;
}

main();

# Connect to the fibs.com server and authenticate
# Return the IO::Socket:INET when prepared
#
sub connect_to_botLock() {
	my $fibs_socket = IO::Socket::INET->new(
		PeerAddr => $FIBS_SERVER_HOST,
		PeerPort => $FIBS_SERVER_PORT,
		Proto    => 'tcp',
		Blocking => 0
	) or die "Connect to $FIBS_SERVER_HOST:$FIBS_SERVER_PORT failed: $!\n";

	my $char            = ' ';
	my $string          = '';
	my $isLooking       = 1;
	my $select          = IO::Select->new($fibs_socket);
	my $bytes_read;
	my $result_ok = 0;
	my $pos;

	while ( $isLooking ) {
		while ( $char ne "\n"  and $isLooking) {
			$select->can_read(1);
			$bytes_read = $fibs_socket->sysread( $char, 1 );
			if ( $char ne "\n" ) {
				$string .= $char if ($bytes_read);
			}
			else {
				print "from fibs login: " . $string . "\n";
			}
			if ( $string eq 'login: ' ) {
				$isLooking = 0;
				print "to fibs login: " . $LOCK_NAME . "\r\n";
				$fibs_socket->syswrite( $LOCK_NAME . "\r" );
			}
		}
		$string = '';
		$char   = ' ';
	}
	$isLooking = 1;
	print "Send username, look for password:\r\n";
	while ( $isLooking ) {
		while ( $char ne "\n" and $isLooking ) {
			$select->can_read(1);
			$bytes_read = $fibs_socket->sysread( $char, 1 );
			if ( $char ne "\n" ) {
				$string .= $char if ($bytes_read);
			}
			else {
				print "from fibs login: " . $string . "\n";
			}
			if ( $string eq 'password: ' ) {
				$isLooking = 0;
				print "to fibs password\r\n";
				$fibs_socket->syswrite( $LOCK_PASSWD . "\r" );
				$result_ok = 1;
			}
			$pos = index($string, 'Warning: You are already logged in.');
			if ( $pos > 0 ) {
				$isLooking = 0;
				print "Already logged in\r\n";
			}
		}
		$string = '';
		$char   = ' ';
	}
	$isLooking = 1;
	print "after password...\r\n";
	while ( $isLooking and $result_ok ) {
		while ( $char ne "\n" and $isLooking ) {
			$select->can_read(1);
			$bytes_read = $fibs_socket->sysread( $char, 1 );
			if ( $char ne "\n" ) {
				if ($bytes_read) {
					$string .= $char;
				} else {
					$isLooking = 0;
				}
			} else {
				#print "from fibs login: " . $string . "\n";
			}
		}
		$string = '';
		$char   = ' ';
	}
	print "exit fibs login: " . $string . "\r\n";
	if ( not $result_ok ) {
		$fibs_socket->close();
		$fibs_socket = 0;
	}
	return $fibs_socket;
}

# Connect to the fibs.com server and find a bot that is not online
# Return the bot name to use
#
sub find_idle_bot() {
	my $fibs_socket = IO::Socket::INET->new(
		PeerAddr => $FIBS_SERVER_HOST,
		PeerPort => $FIBS_SERVER_PORT,
		Proto    => 'tcp',
		Blocking => 0
	) or die "Connect to $FIBS_SERVER_HOST:$FIBS_SERVER_PORT failed: $!\n";

	my $char            = ' ';
	my $string          = '';
	my $isLooking       = 1;
	my $select          = IO::Select->new($fibs_socket);
	my $bytes_read;
	my $result_ok = 0;
	my $pos;
	my $bot=0;
	my $botname="";

	$botname = $_[0];
	printf "Looking for " . $botname . "\r\n";
	while ( $isLooking ) {
		while ( $char ne "\n"  and $isLooking) {
			$select->can_read(1);
			$bytes_read = $fibs_socket->sysread( $char, 1 );
			if ( $char ne "\n" ) {
				$string .= $char if ($bytes_read);
			} else {
				#print "from fibs login: " . $string . "\n";
			}
			if ( $string eq 'login: ' ) {
				$isLooking = 0;
				#print "to fibs login: " . $botname . "\r\n";
				$fibs_socket->syswrite( $botname . "\r" );
			}
		}
		$string = '';
		$char   = ' ';
	}
	$isLooking = 1 if (length($botname));
	#print "Send username, look for password:\r\n";
	while ( $isLooking ) {
		while ( $char ne "\n" and $isLooking ) {
			$select->can_read(1);
			$bytes_read = $fibs_socket->sysread( $char, 1 );
			if ( $char ne "\n" ) {
				$string .= $char if ($bytes_read);
			} else {
				#print "from fibs login: " . $string . "\n";
			}
			if ( $string eq 'password: ' ) {
				$isLooking = 0;
				print "Found offline bot!" . $botname . "\r\n";
				$result_ok = 1;
			}
			$pos = index($string, 'Warning: You are already logged in.');
			if ( $pos > 0 ) {
				$isLooking = 0;
				print "Already logged in\r\n";
				$fibs_socket->syswrite( "\r" ); # Get back to login:
			}
		}
		$string = '';
		$char   = ' ';
	}
	$fibs_socket->close();
	#print "find_bot " . $botname . " " . $result_ok . "\r\n";
	$botname = "" if (not $result_ok);
	return $botname;
}

