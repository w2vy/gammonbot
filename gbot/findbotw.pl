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

# my $day = (localtime)[6];
my $day = "0";

my $FIBS_SERVER_HOST = "fibs.com";
my $FIBS_SERVER_PORT = 4321;
our $LOCK_NAME;
our $LOCK_PASSWD;
our @BOT_NAMES = [];
our $BOT_PASSWD;

sub log_str {
	#open(FH, '>>', "find_bot.log") or die $!;
	#print FH @_;
	#close(FH);

}
# use the next to change any defaults, also bot strentgh file
require "botlist.pl";

sub main() {
	my $gbot;
	# One try: check_bot waits and calls again, so a long wait here only blocks the other slots
	my $tries_left = 1;
	# Hard stop if FIBS stops answering; print nothing so check_bot starts no bot
	$SIG{ALRM} = sub { log_str("Timed out\n"); exit; };
	alarm(480);
	# Connect to fibs.com.
	#
	our $lock_sock = &connect_to_botLock();

	if (not $lock_sock) {
		log_str("null socket\r\n");
	} else {
		# Give the previous bot time to startup
		sleep(20);
		while (1) {
			log_str("Bots for day $day\n");
			require "botlist-$day.pl";
			log_str("Look for bots\r\n");
			$gbot = who_bot($lock_sock, @BOT_NAMES);
			if (length($gbot)) {
				log_str("Found Offline bot! " . $gbot . "\r\n");
				#print "\r\nFound Offline bot! " . $gbot . "\r\n";
				print $gbot;
				#open(FH, '>', "mybot.pl") or die $!;
				#print FH '$BOTID = "' . $gbot . '";' . "\r\n";
				#print FH '$BOTPASS = "' . $BOT_PASSWD . '";' . "\r\n";
				#close(FH);
				last;
			} else {
				#print "No Bot found, tries left " . $tries_left . "\n";
				log_str("No Bot found, tries left " . $tries_left . "\n");
				$tries_left = $tries_left - 1;
				if ($tries_left > 0) {
					sleep(600);
				} else {
					last; # Give up, let someone else try
				}
			}
		}
		$lock_sock->close() if $lock_sock;
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
		Blocking => 0,
		Timeout  => 2
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
				log_str("from fibs login: " . $string . "\n");
			}
			if ( $string eq 'login: ' ) {
				$isLooking = 0;
				log_str("to fibs login: " . $LOCK_NAME . "\r\n");
				$fibs_socket->syswrite( $LOCK_NAME . "\r" );
			}
		}
		$string = '';
		$char   = ' ';
	}
	$isLooking = 1;
	log_str("Send username, look for password:\r\n");
	while ( $isLooking ) {
		while ( $char ne "\n" and $isLooking ) {
			$select->can_read(1);
			$bytes_read = $fibs_socket->sysread( $char, 1 );
			if ( $char ne "\n" ) {
				$string .= $char if ($bytes_read);
			}
			else {
				log_str("from fibs login: " . $string . "\n");
			}
			if ( $string eq 'password: ' ) {
				$isLooking = 0;
				log_str("to fibs password\r\n");
				$fibs_socket->syswrite( $LOCK_PASSWD . "\r" );
				$result_ok = 1;
			}
			$pos = index($string, 'Warning: You are already logged in.');
			if ( $pos >= 0 ) {
				$isLooking = 0;
				log_str("Already logged in\r\n");
			}
		}
		$string = '';
		$char   = ' ';
	}
	$isLooking = 1;
	log_str("after password...\r\n");
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
	log_str("exit fibs login: " . $string . "\r\n");
	if ( not $result_ok ) {
		$fibs_socket->close();
		$fibs_socket = 0;
	}
	return $fibs_socket;
}

# Connect to the fibs.com server and find a bot that is not online
# Return the bot name to use
# Ambiguous name: Try one of: GammonBot_V, GammonBot_II, GammonBot, GammonBot_III, GammonBot_IX, GammonBot_VII, GammonBot_XI, GammonBot_XIII, GammonBot_IV, GammonBot_X, GammonBot_VI, GammonBot_XV, GammonBot_XIV, GammonBot_VIII, GammonBot_XII
sub who_bot() {
	my $chars            = ' ';
	my $string          = '';
	my $isLooking       = 1;
	my $pos;
	my $botname="";
	my $command = "";
	my @args = @_;
	my $fibs_socket = $args[0];
	my @bots = @_[1..$#_];
	my $select = IO::Select->new($fibs_socket);
	my $line;
	my $deadline;

	foreach ( @bots ) {
		$botname = $_;
		$isLooking = 1;
		$string = "";
		$command = "rawwho " . $botname . "\r";
		log_str("Command " . $command . "\n");
		#print "Command " . $command . "\n";
		$fibs_socket->send($command);
		sleep(2);
		$deadline = time() + 30;

		while ( $isLooking ) {
			if ( time() > $deadline ) {
				# No clear answer: assume online rather than start a second copy
				log_str("No answer for " . $botname . "\n");
				last;
			}
			$select->can_read(1);
			$chars = '';
			my $ok = $fibs_socket->recv( $chars, 1024 );
			if ( defined($ok) and $chars eq '' ) {
				log_str("FIBS closed the botLock connection\n");
				return "";
			}
			$string .= $chars;
			# Judge each complete line; unrelated lines (logins, shouts) are skipped
			while ( ($pos = index($string, "\n")) ne -1 ) {
				$line = substr($string, 0, $pos);
				$string = substr($string, $pos + 1);
				if ( index($line, "There is no one called") ne -1
					or index($line, "Ambiguous name") ne -1 ) {
					log_str("Found " . $botname . "\n");
					return $botname;
				}
				if ( index($line, $botname . " ") ne -1 ) {
					$isLooking = 0; # online
					last;
				}
			}
		}
	}
	return "";
}
