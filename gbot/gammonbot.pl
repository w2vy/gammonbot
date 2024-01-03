#!/usr/bin/perl
use strict;
use warnings;
# use diagnostics;

# Include script directory in include search path
# Removed by Perl 5.26 for security reasons, but we still need it.
use FindBin qw( $RealBin );
use lib $RealBin;

# For communication with a forked gnubg
use IPC::Open3 qw(open3);
use Symbol qw(gensym); # perl 5.32

# For file open modes
use Fcntl qw(O_RDONLY);

# For signal handling
use sigtrap qw(handler term_handler normal-signals stack-trace error-signals);

# For timers
# Parameter = Seconds, fractions allowed. E.g. 0.1 = 100 ms. Overrides built-in sleep.
use Time::HiRes qw(sleep);

# To check if arrays contain a scalar value etc.
use List::Util qw(any pairs min);

# Object oriented, non-blocking IO
use IO::Socket::INET;
use IO::Select;

#######################################################################
#            The following are customizable parameters.               *
# These are the global defaults, an include file at the bottom will   *
# be used to override the defaults and to select what settings to be  *
# used to set the strength of the bot
#######################################################################

#if ( $#ARGV < 1 ) {
#	printf "ERROR NOT ENOUGH ARGUMENTS!!! ( $#ARGV )\n";
#	printf "Synopsis: gammonbot.pl BOT_ID BOT_PASSWORD\n";
#	exit;
#}
open( STDERR, ">&STDOUT" ) || die "Can't dup stdout";

our $BOTID   = $ARGV[0];
our $BOTPASS = $ARGV[1];

# from config
our $PATH_TO_GNUBG;
our @ADMIN_LOGINS;
our $ADMIN_EMAIL;
our $user_base;
our $DO_PRINT;
our $USE_STDIN;
our @INITIAL_GREETINGS;
our $tell_count;
our $MAX_MATCH_LENGTH;
our $MAX_SAVED_GAMES;
our $CLEANUP_SAVED;
our $UNLIMITED_ALLOWED;
our @GNUBG_SETUP;
our %assholes;
our $mat_log;
our $maint_mode;
our $FIBS_SERVER_HOST;
our $FIBS_SERVER_PORT;

# from config, no longer used
# FIXME: remove
our $do_fibs_log;
# our $file_base;
our $log_file;
# our $TELL_REPLY;
# our $RESUME_DELAY;
# our $MATCH_DELAY;

$mat_log = 0;

# you may get the password from command line or config.pl

# load config defaults
require "config.defaults.pl";

# The following gets BOTID and BOTPASS from findbot.pl created mybot.pl
require "mybot.pl";

# use the next to change any defaults, also bot strentgh file
require "config.pl";

# $maint_mode = 1;    ##### REMOVE BEFORE DEPLYMENT
# $USE_STDIN  = 1;    ##### REMOVE BEFORE DEPLYMENT

# The string sent to FIBS for login.  The second parameter is a
# name for the client software.  The fourth parameter is the login
# name and the fifth is the password.  Do not change the others.
#
my $LOGIN_LINE = "login ParlorBot 1008 " . $BOTID . " " . $BOTPASS;

#######################################################################
#                 End of customizable parameters.                     *
#######################################################################

#######################################################################
#                 Global Variables                                    *
#######################################################################

# List of my saved matches
my @saved_matches = ();

my $maint_message =
  "Sorry, we are testing some changes right now. Please try again later.";

# Comment this out if I'm ready for the world.
#
if ($maint_mode) {
	print "Maint mode ON\n";
}

# The login name of bots whose tells etc. we want to filter out and parse
#
use constant {

	# Patti's new Manners Bot (warns of high saved game count)
	MISSMANNERS => "MissManners",

	# Old faithful RepBot
	REPBOT => 'RepBotNG'
};

# For parsing fibs boards
use constant {

	#	BD_YOU       => 1,     # "You"
	BD_OPP    => 2,   # opponent's name
	BD_LENGTH => 3,   # match length, 9999 if unlimited
	BD_SCORE1 => 4,   # your match score
	BD_SCORE2 => 5,   # opp's match score
	                  #	BD_P0        => 6,     # bar for player whose home is 25
	     #	BD_P1        => 7,     # negative values are for X, positive for O
	     #	BD_P25       => 31,    # bar for player whose home is 0
	BD_TURN      => 32,    # -1 for X, 1 for O, 0 for game over
	BD_DICE1     => 33,    # your dice (2 values)
	BD_DICE2     => 35,    # opp's dice (2 values)
	BD_CUBE      => 37,    # cube value; 1 if no doubles yet
	BD_MD1       => 38,    # if you may double
	BD_MD2       => 39,    # if opp may double
	BD_DOUBLED   => 40,    # opp has just doubled
	BD_COLOR     => 41,    # -1 if you are X, 1 if you are O
	BD_DIR       => 42,    # -1 if your home is 0, 1 if 25
	BD_ONHOME2   => 46,    # nbr men opp has borne off
	BD_REDOUBLES => 52     # last field of a board
};

# Timer constants. All are in seconds.
#

use constant {
	DELAY_BETWEEN_TWO_COMMANDS_SEND_TO_FIBS => 1.5,

	# Original code: DELAY_WAITING_FOR_REPLY_TO_COMMAND = 10
	DELAY_WAITING_FOR_REPLY_TO_COMMAND => 8,

   # Min. FIBS timeout is 5 minutes, we send keepalives after 1 m = 60 sec
   # Rationale: We also use this to call "show saved" and thus to resume matches
	DELAY_BETWEEN_KEEPALIVES_TO_FIBS => 120,

   # If a player exits their match do not auto resume for 5 mins (tourney time?)
	DELAY_NO_AUTO_RESUME => 300
};


my $GNUBG_MAGIC_PROMPT = "123MaGiCgNuBgPrOmPt456";

my @board             = ();
my @greetings         = ();
my $last_match        = 0;
my $resign_pending    = 0;
my $resign_offered    = 0;
my $crawford_game     = 0;
my $mwc               = 50.00;
my $opp_says_move     = 0;
my $last_play_time    = 0;
my $last_tofibs_time  = 0;
my $repbot_query_time = 0;
my $invite_pending    = 0;
my $no_auto_resume    = time() - DELAY_NO_AUTO_RESUME;

# Array to keep state of blinds for villains. Simplifies implementation.
my @blinded;

# Variables to support a delay between matches against the same opponent.
#
my $last_opponent = "";

# Logging Routines

# FIBS commands we use centralized in one place. Rationale is that the bot can well be logged into
# fibs clones like server.melbg.net:4321 and tigergammon.com:4321 may not support them. At the time of
# this writing (20180130), tigergammon supported all commands we use.

use constant {
	FIBSCMD_TELL           => "tellx",
	FIBSCMD_SHOWSAVED      => "show saved",
	FIBSCMD_SHOWSAVEDCOUNT => "show savedcount",
	FIBSCMD_TIME           => "time",
	FIBSCMD_INVITE         => "invite",
	FIBSCMD_KIBITZ         => "kibitz",
	FIBSCMD_BOARD          => "board",
	FIBSCMD_ACCEPT         => "accept",
	FIBSCMD_JOIN           => "join",
	FIBSCMD_REJECT         => "reject",
	FIBSCMD_ROLL           => "roll",
	FIBSCMD_BYE            => "bye",
	FIBSCMD_LEAVE          => "leave",
	FIBSCMD_RESIGN_N       => "resign normal",
	FIBSCMD_RESIGN_G       => "resign gammon",
	FIBSCMD_RESIGN_B       => "resign backgammon",
	FIBSCMD_BLIND          => "blind",
	FIBSCMD_SHOW_WATCHERS  => "show watchers",
	FIBSCMD_DOUBLE         => "double",
	FIBSCMD_MESSAGE        => "message"
};

# After we see an invitation, FIBS *might* send us an additional line
# warning about a saved match but not having the name of the inviter.
# Therefore we have to keep track of who invited us last, and to what
# type of match.
#
my $last_inviter = "";
my %inviters     = ();
my %saved_count  = ();

# This is the time() at which we will resend a "board" request to FIBS
# if a board is not yet received.
#
my $board_expected = 0;

# Globals needed for computing position and match IDs.
#
my @bin_array = ();

#     0         1         2         3         4         5         6
# dec 0123456789012345678901234567890123456789012345678901234567890123
use constant BASE64 =>
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

# hex 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
#     0               1               2               3

# Limits at which we will do an emergency exit
my $mem_limit  = 300000;
my $load_limit = 9.0;

#######################################################################
#                             Startup (Main)                          #
#######################################################################

# Connect to fibs.com.
#
my $fibs_socket = &connect_to_fibs();
$last_tofibs_time = time();

# On-Demand forking of gnubg useses these three variables
#
my ( $gnubg_pid, $gnubg_in, $gnubg_out );

# Set Handles to be nonblocking / autoflushing for stdio
#
if ($USE_STDIN) {
	STDIN->blocking(0);
	STDIN->autoflush(1);
}

# Make a bit mask for select. $selector entries for gnubg are added
# dynamically.
#
my $selector = IO::Select->new($fibs_socket);
$selector->add(*STDIN) if ($USE_STDIN);

# Global Input buffers, required because we use nonblocking descriptors.
#
my $stdin_buf = "";
my $gnubg_buf = "";
my $fibs_buf  = "";

# Numeric file descriptors of the input sources. Easier to compare.
#
my $fileno_gnu  = -1;
my $fileno_fibs = $fibs_socket->fileno();
my $fileno_stdin;
$fileno_stdin = STDIN->fileno() if ($USE_STDIN);

# Open log file if enabled
if ($do_fibs_log) {
	open( FIBSLOG, ">", $log_file ) or die("Cannot open ($log_file) log");
	FIBSLOG->autoflush(1);
}
print "fibs log: " . $do_fibs_log . " file " . $log_file . "\n";
#######################################################################
#                            Main Loop                                #
#######################################################################

# Wait for data from somewhere, with a 5-second timeout.
#

for ( ; ; ) {

	# Sleep and wake up after 5 secs, or on data from one or more
	# of the three input sources. Whatever comes first.
	# Iterate over the sources with data
	#

	foreach my $fh ( $selector->can_read(5) ) {
		my $fileno = fileno($fh);

		# Process all lines received so far from gnubg.
		#
		if ( $fileno == $fileno_gnu ) {
			&procUnbufferedInput( $fh, \$gnubg_buf, \&procGnubgLine, 5000 );
		}

		# Process all lines received so far from fibs.
		#
		elsif ( $fileno == $fileno_fibs ) {
			&procUnbufferedInput( $fh, \$fibs_buf, \&procFibsLine, 5000 );
		}

		# Process all lines received so far from stdin.
		#
		elsif ( $USE_STDIN && $fileno == $fileno_stdin ) {
			&procUnbufferedInput( $fh, \$stdin_buf, \&procStdinLine, 1000 );
		}
		else {
			# No Data, we got here via the 5 sec timer
		}
	}

	# Checks for diverse, mostly timer related conditions
	#

	&checkHostCPUandMemoryRessources();
	&checkAFKOpponent();
	&checkHungRepbot();
	&checkResumeMatches();
	&checkFibsKeepalive();

	&dump_handler() if ( length($stdin_buf) > 4000 );
	&dump_handler() if ( length($gnubg_buf) > 4000 );
	&dump_handler() if ( length($fibs_buf) > 4000 );
}

&shutdown();

#######################################################################
#                             Shutdown                                #
#######################################################################

sub shutdown() {
	my $fault_handle = shift;

	if ($fault_handle) {
		print "EOF $fault_handle\n";
		print "GNUBG OUT EOF\n"
		  if ( defined($gnubg_out) && $gnubg_out eq $fault_handle );
		print "GNUBG IN EOF\n"
		  if ( defined($gnubg_in) && $gnubg_in eq $fault_handle );
		print "FIBS EOF\n"
		  if ( defined($fibs_socket) && $fibs_socket eq $fault_handle );
	}

	$gnubg_out->close()   if ($gnubg_out);
	$gnubg_in->close()    if ($gnubg_in);
	$fibs_socket->close() if ($fibs_socket);
	MATLOG->close()       if ($mat_log);
	FIBSLOG->close()      if ($do_fibs_log);

	waitpid( $gnubg_pid, 0 ) if ($gnubg_pid);
	exit(0);
}
#######################################################################
#                             Subroutines                             #
#######################################################################

#######################################################################
#                        Subroutines: IO                              #
#######################################################################

# Read up to $sysread_length bytes from the unbuffered IO-Stream refered
# to by $fh. Append it to global buffer referenced by $global_buffer. Then
# break $global_buffer into as many lines as possible and send them to
# the subroutine references by $handler one by one. Remove the bytes of
# the lines process this way from the $global_buffer.
# Should anything IO-related fail, shut down the bot.
#

sub procUnbufferedInput() {
	my ( $fh, $global_buffer, $handler, $sysread_length ) = @_;
	if ( $fh->sysread( my $buffer, $sysread_length ) ) {
		$$global_buffer .= $buffer;

		# Break into lines
		while ( $$global_buffer =~ m/^(.*?)\n(.*)$/s ) {
			$$global_buffer = $2;

			# Call function handle if and only if line is defined
			# and not just whitespace
			$handler->($1) if ( $1 && $1 !~ /^\s*$/ );
		}
	}
	else {
		&shutdown($fh);
	}
}

# Connect to the fibs.com server and authentificate
# Return the IO::Socket:INET when prepared
#
sub connect_to_fibs() {
	my $fibs_socket = IO::Socket::INET->new(
		PeerAddr => $FIBS_SERVER_HOST,
		PeerPort => $FIBS_SERVER_PORT,
		Proto    => 'tcp',
		Blocking => 0
	) or die "Connect to $FIBS_SERVER_HOST:$FIBS_SERVER_PORT failed: $!\n";

	my $char            = ' ';
	my $string          = '';
	my $isAuthenticated = 0;
	my $select          = IO::Select->new($fibs_socket);
	my $bytes_read;
	while ( !$isAuthenticated ) {
		while ( $char ne "\n" ) {
			$select->can_read(1);
			$bytes_read = $fibs_socket->sysread( $char, 1 );
			if ( $char ne "\n" ) {
				$string .= $char if ($bytes_read);
			}
			else {
				do_log_line("from fibs login: " . $string);
			}
			if ( $string eq 'login: ' ) {
				$isAuthenticated = 1;
				print "to fibs login: " . $LOGIN_LINE . "\r\n";
				$fibs_socket->syswrite( $LOGIN_LINE . "\r\n" );
			}
		}
		$string = '';
		$char   = ' ';
	}
	return $fibs_socket;
}

# Run gnubg and make pipes for its stdin and stdout.
# Redirect stderr to stdout to work around that newer versions of gnubg output
# some of their messages to stderr which used to go to stdout.
#

sub connect_to_gnubg() {
	my ( $in, $out) = (gensym, gensym);
	my $pid;
	do_log_line("enter connect_to_gnubg");

	# The actual fork
	eval {
		$pid =
		  open3( $in, $out, undef, $PATH_TO_GNUBG,
			( "--tty", "--quiet", "--no-rc" ) );
	};
	die "Cannot open3 gnubg binary from '$PATH_TO_GNUBG': $@\n" if $@;

	$out->blocking(0);
	$in->autoflush(1);

	# Initialize gnubg instance with our settings
	# The responses to the commands will be read in the main loop.
	#
	foreach (@GNUBG_SETUP) {

		# print "To gnubg setup: " . $_ . "\n";
		$in->syswrite( $_ . "\n" );
	}
	# Explicitly set a prompt, as newer and older versions differ here
	# Some versions don't show one, others to in lines read from gnubg. So
	# let's take control over that explicitly.
	$in->syswrite("set prompt " . $GNUBG_MAGIC_PROMPT . "\n");
	do_log_line("exit connect_to_gnubg with PID=$pid IN=$in OUT=$out");
	return ( $pid, $in, $out );
}

sub load_gnubg() {
	do_log_line("enter load_gnubg");
	( $gnubg_pid, $gnubg_in, $gnubg_out ) = &connect_to_gnubg();
	$gnubg_buf  = "";
	$fileno_gnu = $gnubg_out->fileno();
	$selector->add($gnubg_out);
	do_log_line("exit load_gnubg");
}

sub unload_gnubg() {
	return unless &is_gnubg_loaded();
	do_log_line("unload_gnubg");
	$selector->remove($gnubg_out);
	$fileno_gnu = -1;
	$gnubg_buf  = "";
	&toGnubg("exit");
	$gnubg_in->close();
	$gnubg_out->close();
	waitpid( $gnubg_pid, 0 );
	$gnubg_pid = undef;
	$gnubg_in  = undef;
	$gnubg_out = undef;
}

sub load_gnubg_on_demand() {
	return if &is_gnubg_loaded();
	&load_gnubg();
}

sub is_gnubg_loaded() {
	return defined($gnubg_in) && defined($gnubg_out) && defined($gnubg_pid);
}

sub do_log_line($) {
	my $line = shift;
	if ($DO_PRINT) {
		print $line . "\n";
	}
	if ($do_fibs_log) {
		print FIBSLOG $line . "\n";
	}
}

sub toFibs($$) {
	my ( $command, $line ) = @_;
	my $cmd = $line ? $command . " " . $line : $command;
	$fibs_socket->syswrite( $cmd . "\r\n" );
	&do_log_line( "To FIBS: " . $cmd );
	$last_tofibs_time = time();
}

sub toGnubg($) {
	my $line = shift;
	$gnubg_in->syswrite( $line . "\n" );
	&do_log_line( "To gnubg: " . $line );
}
#######################################################################
#                   Subroutines: Timers in main loop                  #
#######################################################################

# Deal with time-wasting clods who walk away from the keyboard.
#

sub checkAFKOpponent() {
	return unless $last_play_time;
	return if time() < $last_play_time + 60;
	return if &isAdmin($last_opponent);

	if ( time() < ( $last_play_time + 180 ) ) {
		&toFibs( FIBSCMD_KIBITZ, "Are you there?" );
		$last_play_time = time() - 180;
	}
	elsif ( time() > ( $last_play_time + 360 ) ) {
		&toFibs(FIBSCMD_LEAVE);
		&do_log_line("DEBUG: $last_opponent dropped me");
		&onEndMatch();
		$last_play_time = 0;
		sleep(DELAY_BETWEEN_TWO_COMMANDS_SEND_TO_FIBS);
	}

}

# Check if we are waiting for a hung RepBot.  In that case we
# cannot filter out droppers.
#

sub checkHungRepbot() {
	return unless $repbot_query_time;
	return
	  if time() <= $repbot_query_time + DELAY_WAITING_FOR_REPLY_TO_COMMAND;

	$repbot_query_time = 0;
	if ( $last_inviter && $inviters{$last_inviter} ) {
		delete $inviters{$last_inviter};
		&toFibs( FIBSCMD_JOIN, $last_inviter );
	}
}

# Try to resume matches.
#

sub checkResumeMatches() {
	return if $maint_mode;
	return if $last_play_time;
	return unless scalar(@saved_matches);    # non-empty list
	return if time() < $no_auto_resume;

	my $candidate = $saved_matches[0];

	my $doit = &test_resume($candidate);
	&do_log_line("Saved: @saved_matches");
	&do_log_line( "Test $doit for " . $candidate );

	if ( $doit == -99999 || $doit == 0 ) {
		$invite_pending = time();
		&toFibs( FIBSCMD_INVITE, $candidate );
		sleep(DELAY_BETWEEN_TWO_COMMANDS_SEND_TO_FIBS);

		# Wording of the warning done by Patti and greenlighted to send it here.
		&toFibs( FIBSCMD_TELL,
			$candidate
			  . " You will pay a penalty of 15 or more rating points if you let this match expire unfinished."
		);
		shift(@saved_matches);
	}
}

# Do something if n minutes go by with no activity.  Hopefully this
# will keep FIBS from logging us off.
#

sub checkFibsKeepalive() {
	return
	  if time() <= $last_tofibs_time + DELAY_BETWEEN_KEEPALIVES_TO_FIBS;
	if ( $last_play_time == 0 ) {
		&toFibs(FIBSCMD_SHOWSAVED);
	}
	else {
		&toFibs(FIBSCMD_TIME);
	}
}

# Check my memory usage and machine load
# If they are too high then GET OUT!
#

sub checkHostCPUandMemoryRessources() {
	return
	  if ( &my_memory_usage() < $mem_limit);

#	  if ( &my_memory_usage() < $mem_limit
#		&& &get_load_average() < $load_limit );

	my $exitmsg =
	    "Emergency Exit $BOTID Mem "
	  . &my_memory_usage()
	  . " Limit $mem_limit Load "
	  . &get_load_average()
	  . " Limit $load_limit";
	&toFibs( FIBSCMD_MESSAGE, 'Tom ' . $exitmsg );
	&toFibs( FIBSCMD_MESSAGE, 'inim ' . $exitmsg );
	&shutdown($exitmsg);

}
#######################################################################
#                        Subroutines: Gnubg IDs                       #
#######################################################################

# Save an integer value into the given bitstring offset and length.
#
sub setBits($$$) {
	my ( $position, $length, $value ) = @_;

	# starting with low order bits of both the source and target.
	# my $bin_index = $pos;

	while ( $length-- > 0 ) {
		$bin_array[ ( $position & 0xfff8 ) + 7 - ( $position & 7 ) ] = 1
		  if ( $value & 1 );
		++$position;
		$value = int( $value / 2 + 0.1 );
	}
}

# Convert bits to Base64.
#
sub getBase64($) {
	my $result = "";
	my $k      = 0;

	for ( my $i = shift ; $i > 0 ; --$i ) {
		my $cum = 0;
		for ( my $j = 6 ; $j > 0 ; --$j ) {
			$cum = $cum + $cum + $bin_array[ $k++ ];
		}
		$result .= substr( BASE64, $cum, 1 );
	}

	return $result;
}

# Compute the gnubg position ID for a given FIBS @board.
# See http://www.cs.arizona.edu/~gary/backgammon/positionid.html
#
sub getPositionId() {
	@bin_array = (0) x 84;
	my $bin_index = 0;

	my $pnt;

	# The layout sent first depends on whose turn it is.  Our choice
	# is reversed from the spec but is what works with gnubg.
	# The FIBS turn is unreliable if a double is pending.

	my $turn = $board[BD_COLOR] * $board[BD_TURN];    # -1 if opp, 1 if me
	my $turncolor = $board[BD_TURN];    # checker color of the player on turn
	if ( $board[BD_DOUBLED] ) {
		$turn      = -1;
		$turncolor = 0 - $board[BD_COLOR];
	}

	# This will do the opponent's checkers if it's my turn, otherwise mine.
	for ( $pnt = 1 ; $pnt < 26 ; ++$pnt ) {
		my $ix = 6 + ( ( $board[BD_DIR] * $turn > 0 ) ? $pnt : ( 25 - $pnt ) );
		my $count = $board[$ix] * $turncolor;
		while ( $count < 0 ) {
			$bin_array[ ( $bin_index & 0xfff8 ) + 7 - ( $bin_index & 7 ) ] = 1;
			++$bin_index;
			++$count;
		}
		++$bin_index;
	}

	# This will do my checkers if it's my turn, otherwise the opponent's.
	for ( $pnt = 1 ; $pnt < 26 ; ++$pnt ) {
		my $ix = 6 + ( ( $board[BD_DIR] * $turn < 0 ) ? $pnt : ( 25 - $pnt ) );
		my $count = $board[$ix] * $turncolor;
		while ( $count > 0 ) {
			$bin_array[ ( $bin_index & 0xfff8 ) + 7 - ( $bin_index & 7 ) ] = 1;
			++$bin_index;
			--$count;
		}
		++$bin_index;
	}

	return &getBase64(14);
}

# Compute a gnubg match ID from its various integer components.
#
sub getMatchId() {
	my (
		$cube, $cubeowner, $onroll, $crawford, $turn, $doubled,
		$die1, $die2,      $length, $score1,   $score2
	) = @_;

	@bin_array = (0) x 72;

# This is a 0-based method call, the comments are 1-based. Substract 1 to make them applicable.
	&setBits( 0, 4, int( log($cube) / log(2) + 0.1 ) );
	&setBits( 4, 2, $cubeowner );    # 0 = player 0, 1 = player 1, 3 = centered
	&setBits( 6, 1, $onroll );       # who is on roll
	&setBits( 7, 1, $crawford );     # if this is the crawford game
	                                 # Bit 9-11 is the game state:
	                                 # 000 for no game started,
	                                 # 001 for playing a game,
	                                 # 010 if the game is over,
	                                 # 011 if the game was resigned,
	      # or 100 if the game was ended by dropping a cube.
	&setBits( 8,  3, 1 );           # gamestate = playing
	&setBits( 11, 1, $turn );       # who needs to take action right now
	&setBits( 12, 1, $doubled );    # if double is pending?
	   # FIXME: https://www.gnu.org/software/gnubg/manual/html_node/A-technical-description-of-the-Match-ID.html
	   # Bit 14-15 indicates whether an resignation was offered.
	   # 00 for no resignation,
	   # 01 for resign of a single game,
	   # 10 for resign of a gammon,
	   # or 11 for resign of a backgammon.
	   # The player offering the resignation is the inverse of bit 12,
	   # e.g., if player 0 resigns a gammon then bit 12 will be 1
	   # (as it is now player 1 now has to decide whether to accept or reject the resignation)
	   # and bit 13-14 will be 10 for resign of a gammon.
	&setBits( 15, 3,  $die1 );      # if dice are 0 then roll is needed
	&setBits( 18, 3,  $die2 );
	&setBits( 21, 15, $length );    # match length
	&setBits( 36, 15, $score1 );    # player 0 (gnubg) score
	&setBits( 51, 15, $score2 );    # player 1 (opponent) score

	return &getBase64(12);
}

# Tell GnuBG the current match and board details.
#
sub setBoard() {

	# These refer to the player number: 0 = gnubg(me), 1 = opponent.
	# Note that when a double is pending, the turn reported by FIBS
	# seems to be unreliable.
	#
	my $turn = &isBotTurn() ? 0 : 1;
	my $onroll = $turn;
	if ( $board[BD_DOUBLED] ) {
		$turn   = 0;
		$onroll = 1;
	}

	my $matchid = &getMatchId(
		int( $board[BD_CUBE] ),
		$board[BD_MD1]
		? ( $board[BD_MD2] ? 3 : 0 )
		: ( $board[BD_MD2] ? 1 : 3 ),
		$onroll,
		$crawford_game,
		$turn,
		$board[BD_DOUBLED] ? 1 : 0,
		int( $board[ BD_DICE1 + $onroll + $onroll ] ),
		int( $board[ BD_DICE1 + $onroll + $onroll + 1 ] ),
		( $board[BD_LENGTH] > 64 ) ? 0 : int( $board[BD_LENGTH] ),
		int( $board[BD_SCORE1] ),
		int( $board[BD_SCORE2] )
	);
	&toGnubg( "set gnubgid " . &getPositionId() . ':' . $matchid );
}

#######################################################################
#                        Subroutines: FIBS tidbits                    #
#######################################################################

sub blindUser($) {
	my $user = shift;
	return if ( any { $_ eq $user } @blinded );
	push @blinded, $user;
	&toFibs( FIBSCMD_BLIND, $user );
}

# Ask FIBS for the board state and remember when we did so.
#
sub requestBoard() {
	$board_expected = time() + DELAY_WAITING_FOR_REPLY_TO_COMMAND;
	&toFibs(FIBSCMD_BOARD);
}

# Check if the invitation from this person is acceptable to us.
#
sub testinvite($) {
	my $who = shift;
	return 1 if &isAdmin($who);

	if ( $maint_mode && !&isAdmin($who) ) {
		&toFibs( FIBSCMD_TELL, "$who $maint_message" );
		return 0;
	}
	return 1;
}

# Check if the invitation from this person is acceptable to us.
#
sub test_resume($) {
	my $who = shift;
	my $dt  = 0;

	if ( $invite_pending
		&& ( time() - $invite_pending ) < DELAY_WAITING_FOR_REPLY_TO_COMMAND )
	{
		$dt =
		  ( DELAY_WAITING_FOR_REPLY_TO_COMMAND + 1 - time() + $invite_pending );
	}
	if ( $maint_mode && !&isAdmin($who) ) {
		if ( $dt == 0 ) {
			$dt = -99999;
		}
		else {
			$dt = -$dt;
		}
	}
	return $dt;
}

sub testresume($) {
	my $who = shift;
	my $dt  = &test_resume($who);

	if ( $dt < 0 ) {
		&toFibs( FIBSCMD_TELL, "$who $maint_message" );
		return 0;
	}
	if ( $dt > 0 ) {
		&toFibs( FIBSCMD_TELL,
			    "$who Another invitiation is pending. Try again in "
			  . $dt
			  . " seconds if I'm still not playing then." );
		return 0;
	}
	return 1;
}

# Get ready for a new game.
#
sub gameCleanup() {
	$resign_pending = 0;
	$resign_offered = 0;
	$mwc            = 50.00;
	$crawford_game  = 0;
	$opp_says_move  = 0;
	$last_play_time = time();
}

# Starting or Resumng a match
#
sub onStartMatch() {
	@saved_matches = ();
	&toFibs(FIBSCMD_SHOW_WATCHERS);
	&load_gnubg();
}

# Called when a match is over
#
sub onEndMatch() {
	&toFibs(FIBSCMD_BYE) if ($last_match);
	if ($mat_log) {
		close(MATLOG);
		my $oldfn = $user_base . "/matches/" . $BOTID . ".txt";
		my $newfn = "data/finshed/" . $last_opponent . "_" . time . ".txt";
		move( $oldfn, $newfn );
	}
	&notPlaying();
}

# Stopped playing (finshed or they left)
#
sub notPlaying() {

	# Let's be agressive about resuming saved matches
	&toFibs(FIBSCMD_SHOWSAVED);
	$last_play_time = 0;
	&unload_gnubg();

}

#######################################################################
#                        Subroutines: Macros                          #
#######################################################################

# Return true if a given nick is a bot administrator
#
sub isAdmin($) {
	my $nick = shift;
	if ( any { $_ eq $nick } @ADMIN_LOGINS ) {
		return 1;
	}
	return 0;
}

sub isBotTurn() {
	return $board[BD_COLOR] * $board[BD_TURN] > 0 ? 1 : 0;  # -1 if opp, 1 if me
}

# Return true if the string in the first parameter
# starts with the string in the second parameter
# i.e. Prefix match
# this method is ca. 10 times faster than $string =~ m/^\Q$prefix\E/
# this method is ca. 5 times faster than index($string, $needle) == 0

sub startsWith($$) {
	return substr( $_[0], 0, length( $_[1] ) ) eq $_[1];
}

#######################################################################
#                        Subroutines: Unsorted stuff                  #
#######################################################################

###
# Process a line we received from RepBot.

sub onRepbotResponse($) {
	my $repline = shift;

	if (   $repline =~ m/^User (\w+) has no .*/
		|| $repline =~ m/^(\w+)'s reputation is .*\)/ )
	{
		my $cnt = $saved_count{$1} ? $saved_count{$1} : 0;

		#&toFibs("$cmd_tell $1 you have $cnt saved games");
		if ( $cnt == 0 || $cnt < $MAX_SAVED_GAMES || &isAdmin($1) ) {
			if ( $inviters{$1} ) {   # may be false if a match should be resumed
				delete $inviters{$1};
				&toFibs( FIBSCMD_JOIN, $1 );
			}
		}
		else {
			delete $inviters{$1};
			&toFibs( FIBSCMD_TELL,
				"$1 Please finish some of your $2 saved games first." );
			$invite_pending = 0;
		}
	}
	else {
		&do_log_line(
			REPBOT . " said '" . $repline . " which I do not understand." );
	}
}

sub onAdminLine($$) {
	my ( $myadmin, $adminline ) = @_;
	if ( &startsWith( $adminline, "last" ) ) {
		$last_match = 1;
		&toFibs( FIBSCMD_TELL, $myadmin . " logging off after this match." );
	}
	elsif ( &startsWith( $adminline, "logging" ) ) {
		if ($DO_PRINT) {
			$DO_PRINT = 0;
			&toFibs( FIBSCMD_TELL, $myadmin . " printing turned off" );
		}
		else {
			&toFibs( FIBSCMD_TELL, $myadmin . " printing turned on" );
			$DO_PRINT = 1;
		}
	}
	elsif ( &startsWith( $adminline, "gnubg restart" ) ) {
		&unload_gnubg();
	}
	elsif ( $adminline =~ m/^gnubg (.*)$/ ) {
		my $gnucmd = $1;
		chomp $gnucmd;
		&toFibs( FIBSCMD_TELL, $myadmin . " gnubg command: '" . $gnucmd . "'" );
		&toGnubg($gnucmd);
	}
	elsif ( &startsWith( $adminline, "memory" ) ) {
		my $gnu_mem = defined($gnubg_pid) ? getMemByPid($gnubg_pid) : 0;
		my $my_mem  = getMemByPid($$);
		my $max_mem = $gnu_mem + $my_mem;
		&toFibs( FIBSCMD_TELL,
			    $myadmin
			  . " Mem GNU "
			  . $gnu_mem
			  . " Perl "
			  . $my_mem . " Sum "
			  . $max_mem
			  . " Limit "
			  . $mem_limit
			  . " Load "
			  . get_load_average()
			  . " Limit "
			  . $load_limit );
	}
	else {
		&toFibs($adminline);
	}

}

# Parse and act on anything FIBS sends that we might be interested in.
#
sub procFibsLine($) {
	my $line = shift;

	# Filter out some clutter to make debugging easier.
	#

	return
	  if ( &startsWith( $line, '5 ' )
		&& !&startsWith( $line, "5 $BOTID " ) );
	return
	  if ( any { &startsWith( $line, $_ ) } ( '7 ', '8 ', '13 ', '16 ', '6' ) );

	&do_log_line( "from FIBS: " . $line );

	# If we are expecting a board and one has not shown up for a while,
	# there are a few things that might have gone wrong.  FIBS has a bug
	# where autoroll does not happen on resuming a match; or it might
	# have lost our "board" command, or otherwise gotten confused.
	# In the past severe lag has also been a problem.
	#
	if ( $board_expected && time() > $board_expected ) {
		if (   &isBotTurn()
			&& !$board[BD_MD1]
			&& !$board[BD_DICE1]
			&& !$board[BD_DOUBLED] )
		{
			&toFibs(FIBSCMD_ROLL);
			$board_expected = time() + DELAY_WAITING_FOR_REPLY_TO_COMMAND;
		}
		else {
			&requestBoard();
		}
	}

	# Someone else does say or tell.
	#
	if ( $line =~ m/^12 (\w+) (.*)$/ ) {

		# RepBot tells us about the inviter.
		#
		if ( $1 eq REPBOT ) {
			$repbot_query_time = 0;
			&onRepbotResponse($2);
		}

		# The administrator has a command for us.
		#
		elsif ( &isAdmin($1) ) {
			&onAdminLine( $1, $2 );
		}
		elsif ( $1 eq MISSMANNERS ) {

			# We will not discuss with MM
		}

		# Anyone else gets the standard response.
		# FIXME: cleanup and re-enable tellreply
		else {
			if ( defined( $saved_matches[0] ) && $1 eq $saved_matches[0] ) {
				shift(@saved_matches);
				$invite_pending = 0;    # Discard invite
			}
			elsif ( $tell_count < 10 ) {

				#   &toFibs("$cmd_tell $1 $TELL_REPLY");
				$tell_count = $tell_count + 1;
			}
		}
	}

	# If RepBot is offline, we cannot filter out droppers.
	#
	elsif ( &startsWith( $line, '** There is no one called ' . REPBOT ) ) {
		$repbot_query_time = 0;
		if ( $last_inviter && $inviters{$last_inviter} ) {
			delete $inviters{$last_inviter};

			#print "Join match with $last_inviter";
			&toFibs( FIBSCMD_JOIN, $last_inviter );
		}
	}

	# if we invite a player and they are not online (anymore) remove
	# them from the saved_matches
	#
	elsif ( $line =~ m/^\*\* There is no one called (\w+)\s*$/ ) {
		if ( defined( $saved_matches[0] ) && $1 eq $saved_matches[0] ) {
			shift(@saved_matches);
			$invite_pending = 0;    # Discard invite
		}
	}

	# if we invite a player and they are already playing, remove them from
	# the saved_matches
	#
	elsif ( $line =~ m/^\*\* (\w+) is already playing with someone else.\s*$/ )
	{
		if ( defined( $saved_matches[0] ) && $1 eq $saved_matches[0] ) {
			shift(@saved_matches);
			$invite_pending = 0;    # Discard invite
		}
	}

	# Don't accept a new-rated-match invitation right away; first check if
	# they are a dropper or already have a saved rated match with us. Also
	# reject 2-point matches which have the same luck factor as 1-pointers
	# but (on FIBS) give the lower-rated player better odds.
	#
	elsif ( $line =~ m/^(\w+) wants to play a (\d+) point match with you./ ) {
		$last_play_time = 0;
		if ( $assholes{$1} ) {
			&do_log_line( "Banned Inviter: " . $1 );
			print "Banned Inviter: " . $1;
		}
		if ( !$assholes{$1} && &testinvite($1) ) {
			if ( $2 > $MAX_MATCH_LENGTH ) {
				&toFibs( FIBSCMD_TELL,
"$1 No matches greater than $MAX_MATCH_LENGTH points, please."
				);
			}
			elsif ( $2 == 2 ) {
				&toFibs( FIBSCMD_TELL,
					"$1 Sorry, 2-pointers do not agree with me. :)" );
			}
			else {
				if ($CLEANUP_SAVED) {
					&toFibs( FIBSCMD_TELL,
"$1 I am cleaning up my saved matches, I only will Resume matches"
					);
				}
				else {
					$last_inviter   = $1;
					$inviters{$1}   = $2;
					$invite_pending = time();
					&toFibs( FIBSCMD_SHOWSAVEDCOUNT, $1 );
					sleep(DELAY_BETWEEN_TWO_COMMANDS_SEND_TO_FIBS);
					&toFibs( FIBSCMD_TELL, REPBOT . " ask $1" );
					$repbot_query_time = time();
				}
			}
		}
	}

	# Similarly for unlimited matches.
	#
	elsif ( $line =~ m/^(\w+) wants to play an unlimited match with you./ ) {
		$last_play_time = 0;
		if ($UNLIMITED_ALLOWED) {
			if ( !$assholes{$1} && &testinvite($1) ) {
				$last_inviter   = $1;
				$inviters{$1}   = 9999;
				$invite_pending = time();
				&toFibs( FIBSCMD_SHOWSAVEDCOUNT, $1 );
				sleep(DELAY_BETWEEN_TWO_COMMANDS_SEND_TO_FIBS);
				&toFibs( FIBSCMD_TELL, REPBOT . " ask $1" );
				$repbot_query_time = time();
			}
		}
		else {
			&toFibs( FIBSCMD_TELL,
				"$1 Sorry, I do not play unlimited matches." );
		}
	}

	# Don't use join to resume a match.  Because of race conditions
	# that can be abused by cheaters, we can never be really sure what
	# type of match we are joining.  Invite them instead.
	#
	elsif ( $line =~ m/^(\w+) wants to resume a saved match with you./ ) {
		$last_play_time = 0;
		if ( !$assholes{$1} && testresume($1) == 1 ) {
			$invite_pending = time();

			#print "Invite $1 to Resume a match\n";
			&toFibs( FIBSCMD_INVITE, $1 );
		}
	}

	# FIBS tells us we have a saved rated match with this inviter.
	# Let's cut the crap and invite them to resume it.
	#
	elsif ( $line =~ m/^WARNING: Don't accept if (.*) point match!/ ) {
		if ($last_inviter) {
			&toFibs( FIBSCMD_INVITE, $last_inviter );
			sleep(DELAY_BETWEEN_TWO_COMMANDS_SEND_TO_FIBS);
			&toFibs( FIBSCMD_TELL,
				$last_inviter
				  . " We have a saved match, please resume it now." );
			delete $inviters{$last_inviter};
			$last_inviter = "";
		}
	}

	# How many saved matches do we have?
	#
	elsif ( $line =~ m/^(\w+) has (\d+) saved game/ ) {
		$saved_count{$1} = $2;
	}

	# Between games of a match.
	#
	elsif (
		&startsWith( $line, "Type 'join' if you want to play the next game" ) )
	{
		if ( $last_match && $board[BD_LENGTH] > 99 ) {
			&toFibs(FIBSCMD_BYE);
		}
		else {
			&toFibs(FIBSCMD_JOIN);
		}
	}

	# If a new match is starting, initialize an array of greeting lines that
	# will be sent piecemeal during the first few moves of the game.
	#
	elsif (
		$line =~ m/^\*\* You are now playing a (\d+) point match with (\w+)/ )
	{
	#     $line =~ m/^\*\* You are now playing an unlimited match with (\w+)/) {
		$last_opponent = $2;
		&onStartMatch();
		@greetings  = @INITIAL_GREETINGS;
		$tell_count = 0;
		$user_base  = "data/$2";

		if ($mat_log) {
			my $fname = $user_base . "/matches/" . $BOTID . ".txt";
			open( MATLOG, ">", $fname )
			  or die("Cannot open ($fname) match log");
			MATLOG->autoflush(1);
			print MATLOG "# Start a $1 point match with $2\n";
			print MATLOG "set player 0 name $BOTID\n";
			print MATLOG "set player 0 human\n";
			print MATLOG "set player 1 name $2\n";
			print MATLOG "set player 1 human\n";
			print MATLOG "new match $1\n";
		}
	}

	# Make sure we have the starting board when a match is resumed.
	#
	# You are now playing with test. Your running match was loaded.

	elsif ($line =~ m/^You are now playing with (\w+)\. Your running/
		|| $line =~ m/^(\w+) has joined you\. Your running/ )
	{
		$last_opponent = $1;
		&onStartMatch();
		&requestBoard();
		&gameCleanup();
		$tell_count = 0;
		$user_base  = "data/$1";
		if ($mat_log) {
			my $fname = $user_base . "/matches/" . $BOTID . ".txt";
			open( MATLOG, ">>", $fname )
			  or die("Cannot open ($fname) match log");
			MATLOG->autoflush(1);
			print MATLOG "# Resume match with $1\n";
		}
	}

	# Greet watchers and handle watches set while match is already
	# running. Keep in sync with code for "show watcher" handling below.
	#
	elsif ($line =~ m/^(\w+) is watching you\./
		|| $line =~ m/^(\w+) starts watching / )
	{
		my $w = $1;
		if ( $assholes{$w} ) {
			&blindUser($w);
		}
		else {
			&toFibs( FIBSCMD_KIBITZ, "Hi $w." );
		}
		if ( &isAdmin($w) ) {
			&toFibs( FIBSCMD_TELL, "Admin priviledges granted." );
		}
	}

	# Handle "show watchers" output lines
	elsif ( $line =~ m/^(\w+) is watching \w+\./ ) {
		if ( $assholes{$1} ) {
			&blindUser($1);
		}
	}

	# Board state message.
	#
	elsif ( &startsWith( $line, "board:" ) ) {
		$board_expected = 0;
		@board = split( /:/, $line );

		do_log_line( "DEBUG: board Score "
			  . $board[BD_SCORE1] . " - "
			  . $board[BD_SCORE2]
			  . " MYTurn1 "
			  . $board[BD_TURN] * $board[BD_COLOR]
			  . " Dice "
			  . $board[BD_DICE1] . "-"
			  . $board[BD_DICE1 + 1] . " MD1 "
			  . $board[BD_MD1] . " MD2 "
			  . $board[BD_MD2]
			  . " Doubled "
			  . $board[BD_DOUBLED] );

	   # This is possible if they send a legal invite immediately followed by
	   # an invite exceeding our maximum match length.  This solution is radical
	   # since it will keep them from playing with us for 3 months or so.
	   # Probably what we really need to do is always invite, never join.
	   #
		if (   $board[BD_LENGTH] > $MAX_MATCH_LENGTH
			&& $board[BD_LENGTH] != 9999 )
		{
			&toFibs( FIBSCMD_KIBITZ,
				"No soup for you.  Try again in 3 months." );
			sleep(DELAY_BETWEEN_TWO_COMMANDS_SEND_TO_FIBS);
			&toFibs(FIBSCMD_LEAVE);
			$board_expected = 0;
			&gameCleanup();
			&notPlaying();
			$assholes{ $board[BD_OPP] } = 1;
		}

		# If it's my turn and (the dice are rolled or I'm allowed to double),
		# or if I was just doubled...
		#
		elsif ( ( &isBotTurn() && ( $board[BD_MD1] || $board[BD_DICE1] ) )
			|| $board[BD_DOUBLED] )
		{
			# print "MAT: SET dice $board[$BD_DICE1] and $board[$BD_DICE2]\n"
			# if ($mat_log);

		# On-demand check is required here because fibs autojoin may send us
		# a board: without any preceding matchstart/matchend messages sometimes,
		# right after login and resume.
		#
			&load_gnubg_on_demand();
			&setBoard();
			&toGnubg("hint 1");
		}

		# I sometimes see folks getting indignant with a robot when they are not
		# aware it's their own turn.  This oughta shut them up.
		#
		elsif ($opp_says_move) {
			if ( $board[BD_TURN] == 0 ) {
				&toFibs(FIBSCMD_JOIN);    # just in case our own join got lost
				sleep(DELAY_BETWEEN_TWO_COMMANDS_SEND_TO_FIBS);
				&toFibs( FIBSCMD_KIBITZ,
					'It is nobody\'s turn. Perhaps you need to join?' );
			}
			elsif ( &isBotTurn() ) {

			   # It seems FIBS can forget to autoroll, for example if we reject
			   # a resignation that came just before the autoroll should happen.
				&toFibs(FIBSCMD_ROLL);
			}
			elsif ( $board[BD_DICE2] ) {
				&toFibs( FIBSCMD_KIBITZ,
					    "I think you still need to play your "
					  . $board[BD_DICE2] . "-"
					  . $board[ BD_DICE2 + 1 ]
					  . " roll." );
			}
			else {
				&toFibs( FIBSCMD_KIBITZ,
					"FIBS is telling me it's your turn to roll." );
			}
		}

		# If we have to wait for the opp to take her turn, this is a good time
		# to send the next greeting line without confusing the FIBS server.
		#
		elsif ( scalar @greetings ) {
			&toFibs( FIBSCMD_KIBITZ, shift @greetings );
		}

		$opp_says_move  = 0;
		$last_play_time = time();

		# Deal with a nasty FIBS bug; board lines are often missing a line end.
		#
		if ( $board[BD_REDOUBLES] =~ m/^0(.{4,})$/ ) {
			my $tmp = $1;
			$tmp .= ":" . join( ":", @board[ ( BD_REDOUBLES + 1 ) .. $#board ] )
			  if ( $#board > BD_REDOUBLES );
			&do_log_line( "Recycling: " . $tmp );
			&procFibsLine($tmp);
		}
	}

	# Opponent wants to resign.
	#
	elsif ( $line =~ m/^\w+ wants to resign\. You will win (\d+) point/ ) {

		if ( &isBotTurn() ) {

			# We can accept any cube which wins the match no matter what
			if ( $board[BD_SCORE1] + $1 >= $board[BD_LENGTH] ) {
				&toFibs(FIBSCMD_ACCEPT);
			}
			else {
				&toFibs(FIBSCMD_REJECT);
				sleep(DELAY_BETWEEN_TWO_COMMANDS_SEND_TO_FIBS);
				&toFibs( FIBSCMD_KIBITZ,
					"I can only handle this resignation when it's your turn." );
			}
		}

		# Opponent must be on roll.
		#
		else {
			&setBoard();
			$resign_pending = 1;
			&toGnubg( "resign " . int( $1 / $board[BD_CUBE] + 0.1 ) );
			print MATLOG "resign $1\n" if ($mat_log);
		}
	}

	# Work around FIBS bug with "toggle moreboards". After opponent
	# rejected our resign, there is no new board sent automatically.
	# So actively poll it.
	#
	elsif ( $line =~ m/\w+ rejects\. The game continues\./ ) {

		#print "DEBUG: user rejected resign.";
		$resign_offered = 0;
		&requestBoard();
	}

	# If FIBS loses our 'reject' command...
	#
	elsif ( $line =~ m/^\*\* \w+ wanted to resign\./ ) {
		&toFibs(FIBSCMD_REJECT);
	}

	# When opp cannot move we may not get a new board message.
	#
	elsif ( $line =~ m/^\w+ can't move\./ ) {
		&requestBoard();
	}

	# Doubles and redoubles.
	#
	elsif ($line =~ m/^\w+ doubles\./
		|| $line =~ m/^\w+ redoubles to \d+\./ )
	{
		&requestBoard();
		print MATLOG "double\n" if ($mat_log);
	}

	# The opponent leaves the game one way or another
	#
	elsif (
		   $line =~ m/^\*\* Player \w+ has left the game\. The game was saved\./
		|| $line =~ m/^\w+ logs out\. The game was saved\./
		|| $line =~ m/^\w+ drops connection\. The game was saved\./
		|| $line =~ m/^Network error with \w+\. The game was saved\./
		|| $line =~ m/^Connection with \w+ timed out\. The game was saved\./
		|| $line =~
		m/^Closed old connection with user \w+\. The game was saved\./
		|| $line =~ m/^\w+ closes connection with \w+\,/ )
	{
		# They left the match, nothing else to do.
		&do_log_line( "Debug: Player Left the match: '" . $line . "'" );
		close(MATLOG) if ($mat_log);
		&notPlaying();

		# If the player exits the match maybe it is tourney time,
		# do not auto resume for 5 mins
		#
		if ( $line =~
			m/^\*\* Player \w+ has left the game\. The game was saved\./ )
		{
			$no_auto_resume = time() + DELAY_NO_AUTO_RESUME;
			&toFibs( FIBSCMD_TELL,
				    $last_opponent
				  . ' I will not attempt to resume for '
				  . DELAY_NO_AUTO_RESUME / 60
				  . ' minutes.' );
		}
	}

	# Capture rolls and moves for Match Logging (if enabled)
	elsif ( $mat_log && $line =~ m/You rolled (\d+), \w+ rolled (\d+)/ ) {
		print MATLOG "# $line\n";
		print MATLOG "$1 $2\n";
	}
	elsif (
		$mat_log
		&& (   $line =~ m/You roll (\d+) and (\d+)./
			|| $line =~ m/\w+ rolls (\d+) and (\d+)./ )
	  )
	{
		print MATLOG "set Dice $1 $2\n";
	}
	elsif ( $mat_log && $line =~ m/(\w+) makes the first move./ ) {
		print MATLOG "# $1 moves first\n";
	}
	elsif ( $mat_log && $line =~ m/\w+ moves (.*)\./ ) {
		my $str = $1;
		$str =~ s/-/\//g;
		print MATLOG "move $str\n";
	}

	# Attempts to recover from hangs.  Need something better than this.
	# The problem is that FIBS sometimes loses what we send.
	#
	elsif ($line =~ m/^15 \w+ move\s*$/i
		|| $line =~ m/^15 \w+ roll\s*$/i
		|| $line =~ m/^15 \w+ kibitz\s+move\s*$/i )
	{
		$opp_says_move = 1;
		&requestBoard();
	}
	elsif ( $line =~ m/^15 \w+ join\s*$/i ) {
		&toFibs(FIBSCMD_JOIN);
	}

	# Attempt to capture online players we have saved matches
	# with (from Show Saved)
	#
	# To FIBS: show saved
	#**inim                    1                0 -  0
	# *Bosco                   3                2 -  1
	#  mnatokad                5                4 -  3
	#
	elsif ( $line =~ m/\*\*(\w+)\s*\d+\s*\d+\s*-\s*\d+/ ) {
		my $savedwith = $1;

		&do_log_line("We have saved match with $savedwith");
		if ( $last_play_time == 0 ) {

			# Remember the name of the person, unless we already know her
			unless ( any { $_ eq $savedwith } @saved_matches ) {
				push( @saved_matches, $savedwith );
			}
		}
	}

	# More recovery logic.
	#
	elsif ( &startsWith( $line, '** You did already roll' ) ) {
		&requestBoard();
	}

	# End of a match.
	#
	elsif ($line =~ m/^You win the \d+ point match/
		|| $line =~ m/^\w+ wins the \d+ point match/ )
	{
		onEndMatch();
	}

	# New game starts.
	#
	elsif ( &startsWith( $line, 'Starting a new game with ' ) ) {
		&gameCleanup();
	}

	# If we are not playing then we should not be waiting for a board.
	#
	elsif ( &startsWith( $line, '** You\'re not playing.' ) ) {
		$board_expected = 0;
		&gameCleanup();
		&notPlaying();
	}

	# If FIBS tells us this is the Crawford game, don't keep on
	# trying to double at every turn.
	#
	elsif ( &startsWith( $line, '** The Crawford rule doesn' ) ) {
		$crawford_game = 1;
	}

	elsif ( $line =~ m/^\*\* \w+ hasn't responded to your double/ ) {
		&toFibs( FIBSCMD_KIBITZ, "It appears you need to reply to my double." );
	}
	elsif ($line =~ m/^\*\*\* ATTENTION ! FIBS will restart in \d+ second/
		|| $line =~ m/^\*\*\* ATTENTION ! FIBS will shut down in \d+ second/ )
	{
		&toFibs(FIBSCMD_BYE);
	}
}

# Parse an input line from STDIN and do the right thing with it.
#

sub procStdinLine($) {
	my $line = shift;
	&do_log_line( "from stdin: " . $line );

	if ( &startsWith( $line, 'last' ) ) {
		$last_match = 1;
		&toFibs( FIBSCMD_KIBITZ,
			"I will be logging out briefly for maintenance when this "
			  . (
				( $board[BD_LENGTH] > 99 )
				? "game ends."
				: "match ends."
			  )
		);
	}
	else {
		&toFibs($line);
	}
}

# Parse an input line from GnuBG and do the right thing with it.
#
sub procGnubgLine($) {
	my $line = shift;
	# See also: connectToGnubg where this is set
	$line =~ s/$GNUBG_MAGIC_PROMPT//;
	# FIXME: Could also trim and avoid loop completely if possible
	&do_log_line( "from gnubg: " . $line );

	# Gnubg replies to a hint request with a cube decision.
	# See: eval.c#GetCubeRecommendation for the Strings
	#

	if ( $line =~ m/^Proper cube action: (.+)$/ ) {

		# E.g. "Never redouble, take (dead cube)"
		my $action = $1;
		if ( &startsWith( $action, 'Unknown cube decision' ) ) {

			# FIXME
			print "Panic, '$action' from gnubg can not be handled";
		}

		# Split into our own and opponent's action at the comma
		my ( $own_action, $opp_response ) = split( /, /, $action );

		# Let's not do the optional doubles; they either waste time or favor
		# the weaker player. Just roll and move on.

		if (
			any { &startsWith( $own_action, $_ ) }
			( 'No ', 'Too good', 'Optional' )
		  )
		{
			&handleCubeAction( FIBSCMD_ROLL, $opp_response );
		}

		# The bot cubes the opponent
		elsif (
			any { &startsWith( $own_action, $_ ) }
			( 'Double', 'Redouble' )
		  )
		{
			&handleCubeAction( FIBSCMD_DOUBLE, $opp_response );
		}

		# dead cube received, always accept
		elsif ( &startsWith( $own_action, 'Never ' ) ) {
			&handleDeadCube();
		}
		else {
			print
"Error handling cube action '$action'; please report this to $ADMIN_EMAIL.\n";
			&toFibs( FIBSCMD_KIBITZ,
"Error handling cube action '$action'; please report this to $ADMIN_EMAIL."
			);
		}
	}

	# Hint returns this if the cube is already at match value.
	# FIBS allows such doubles but gnubg does not.
	#
	elsif ( &startsWith( $line, 'You cannot double.' ) ) {
		if ( $board[BD_DOUBLED] ) {
			handleDeadCube();
		}
		else {
			&toFibs(FIBSCMD_ROLL);
			$board_expected = time() + DELAY_WAITING_FOR_REPLY_TO_COMMAND;
		}
	}

	# Gnubg is confused, looking for dice from me.
	# We need to move past this. it wants dice, give him some...
	#
	# FIXME: This happens in the context of refused resignations
	# example
	#
	# set lang C
	# set player 1 name opp
	# set confirm new off
	# set rng manual
	# set display on
	# set automatic game off
	#
	# Works:
	# set gnubgid 82wAXAE3AAAAAA:EQGlACAAIAAA
	# hint 1
	#
	# Leads to "Enter Dice:"
	# set gnubgid NwAAwDwbACcCAA:UQmgACAAIAAA
	# resign 1

	#
	elsif ( $line =~ m/^Enter dice: *./ ) {

		# This only leads to trouble, better exit the hard way
		# &toGnubg("1 2");
		&toFibs( FIBSCMD_KIBITZ,
"ERROR: gnubg was confused by your resignation, logging out to reset gnubg and fibs status. I'll be back."
		);
		&shutdown("'Enter dice:' bug panic.");
	}

	# Gnubg replies to a hint request with a move.  We have a lot of
	# work to do here because the moves are "beautified" in strange
	# and wonderful ways.
	#
	elsif ( $line =~ m/^\s+1\. \w+ \d-ply\s+(.*\S)\s+(\S+:.*)$/ ) {
		my $out    = $1 =~ tr/\*//dr;    # the gnubg move with all '*' removed
		my $mwctmp = $2;
		print MATLOG "move $out\n" if ($mat_log);
		my @arr = ();

		my $color = int( $board[BD_COLOR] );
		my $home0 = $board[BD_DIR] < 0;

		if ( $board[BD_DICE1] == 0 || $board[ BD_DICE1 + 1 ] == 0 ) {

			# FIXME: Can this happen?
			&shutdown("Dice are Zero - Bot Spin averted!. Bail out.");
		}

		do_log_line("Hint: Equity $mwctmp");

		{
			my @atmp = split( / /, $out );

			# Expand gnubg moves such as "24/18(2)".
			#
			for ( my $i = 0 ; $i < scalar @atmp ; ++$i ) {

				# Split line into single moves and expand (n) notation
				#
				if ( $atmp[$i] =~ m/^(.+)\((\d)\)/ ) {
					$atmp[$i] = $1;
					for ( my $j = 1 ; $j < $2 ; ++$j ) {
						splice( @atmp, $i + $j, 0, $1 );
					}
				}

				# Copy over to array we keep on working with
				# Format is moves, odd fields is from, even fields is to
				#
				my @move = split( /\//, $atmp[$i] );
				for ( my $j = 1 ; $j < @move ; ++$j ) {
					my $k = scalar @arr;
					$arr[$k] = $move[ $j - 1 ];
					$arr[ $k + 1 ] = $move[$j];

					$arr[$k] = 25 if ( $arr[$k] eq 'bar' );
					$arr[ $k + 1 ] = 0 if ( $arr[ $k + 1 ] eq 'off' );
				}
			}

		}

		# Gnubg may abbreviate moves, e.g. "24/13" instead of "24/18 18/13".
		# I've also seen "18/10(2)" on a 44 roll, and "bar/23*/21(2)" on a 22.
		# FIXME: "bar/23*/21(2)" would cause problems, i do not see it handled
		#
		{
			my ( $die1, $die2 ) =
			  ( $board[BD_DICE1], $board[ BD_DICE1 + 1 ] );

			# Prefer the lower die first to avoid illegal bearoffs.
			( $die1, $die2 ) = ( $die2, $die1 ) if ( $die1 > $die2 );

			for ( my $i = 0 ; $i < scalar @arr ; $i += 2 ) {
				my $movedist = $arr[$i] - $arr[ $i + 1 ];
				if ( $movedist > $die1 && $movedist > $die2 ) {
					my $pnt = $arr[$i] - $die1;
					$pnt = $arr[$i] - $die2
					  if ( $board[ 6 + ( $home0 ? $pnt : ( 25 - $pnt ) ) ] *
						$color < 0 );
					splice( @arr, $i + 2, 0, $pnt, $arr[ $i + 1 ] );
					$arr[ $i + 1 ] = $pnt;
				}
			}
		}

		# A special problem with abbreviations: be suspicious of single-move
		# bearoffs.
		#
		if ( scalar @arr == 2 && $arr[1] == 0 ) {
			my $pnt = $arr[0] - min( $board[BD_DICE1], $board[ BD_DICE1 + 1 ] );

			# Figure out if we could have moved the smaller die number first
			# and then borne off that same checker.  If so, assume it.
			#
			if (   $pnt > 0
				&& $board[ 6 + ( $home0 ? $pnt : ( 25 - $pnt ) ) ] * $color >=
				0 )
			{
				my $pscan = 6;
				for ( ; $pscan > $pnt ; --$pscan ) {
					my $nmen =
					  $board[ 6 + ( $home0 ? $pscan : ( 25 - $pscan ) ) ] *
					  $color;
					last
					  if ( $nmen > 1
						|| ( $pscan != $arr[0] && $nmen > 0 ) );
				}
				if ( $pscan == $pnt ) {
					$arr[2] = $pnt;
					$arr[3] = $arr[1];
					$arr[1] = $pnt;
				}
			}
		}

		# Make sure all moves from the bar come before all other moves.
		#
		for ( my $i = 2 ; $i < scalar @arr ; $i += 2 ) {
			if ( $arr[$i] == 25 && $arr[ $i - 2 ] != 25 ) {
				my $tmp = $arr[ $i - 2 ];
				$arr[ $i - 2 ] = $arr[$i];
				$arr[$i]       = $tmp;
				$tmp           = $arr[ $i - 1 ];
				$arr[ $i - 1 ] = $arr[ $i + 1 ];
				$arr[ $i + 1 ] = $tmp;
				$i             = 0;
			}
		}

		# Also sort bearoffs after non-bearoffs, and bearoffs from lower
		# points after bearoffs from higher points.
		# In one example "3/off 2/off(2)" on a 2-2 roll needed translation
		# to "move 3-1 2-off 2-off 1-off".
		#
		for ( my $i = 0 ; $i < ( scalar @arr - 2 ) ; $i += 2 ) {
			for (
				my $j = $i + 2 ;
				$arr[ $i + 1 ] == 0 && $j < scalar @arr ;
				$j += 2
			  )
			{
				if ( $arr[ $j + 1 ] != 0 || $arr[$i] < $arr[$j] ) {
					my $tmp = $arr[$i];
					$arr[$i]       = $arr[$j];
					$arr[$j]       = $tmp;
					$tmp           = $arr[ $i + 1 ];
					$arr[ $i + 1 ] = $arr[ $j + 1 ];
					$arr[ $j + 1 ] = $tmp;
					$j             = $i;
				}
			}
		}

		$out = "move";

		# Gnubg always reports moves as if the mover's home is 0.
		# That may not be the case with FIBS.  Also we have to translate
		# 25 to bar and 0 to off.
		#
		foreach my $move ( pairs @arr ) {
			my ( $from, $to ) = @$move;
			if   ( $from == 25 ) { $from = "bar" }
			else                 { $from = 25 - $from unless $home0 }

			if   ( $to == 0 ) { $to = "off" }
			else              { $to = 25 - $to unless $home0 }

			$out .= " " . $from . "-" . $to;
		}

		&toFibs($out);
		$board_expected = time() + DELAY_WAITING_FOR_REPLY_TO_COMMAND;

		if ( $mwctmp =~ m/MWC:\s*(\d+\.\d+)%/ ) {
			$mwc = $1;
			do_log_line("MWC is $mwc");
		}
	}

	# FIXME: get rid of gnubg prefix
	# see play.c#NextTurn
	# %s wins a %s and %d point.
	# %s wins a %s and %d points.
	# e.g. "gnubg wins a [single game|gammon|backgammon] and 3 points.
	#
	# FIXME: This was commented out and is not used, what was the idea?
	# FIXME: See gnubg.c#HintResigned
	# FIXME: elsif ($line =~ m/^Correct resign decision  : (\w+)/) {
	#
	# Debug example
	# setgnubgid 4HPwASLgc/ABMA:cCGgADAAAAAE

	elsif ( $line =~ m/^gnubg wins / ) {
		if ($resign_pending) {
			$resign_pending = 0;
			&toFibs(FIBSCMD_ACCEPT);
			print MATLOG "accept\n" if ($mat_log);
		}
	}

	# We follow a resign request (on behalf of the opponent) with a
	# request for pip counts.  That way when we get the pip count
	# response and the offer was not already accepted, we know it was
	# rejected.
	#
	#elsif ($line =~ m/^The pip counts are:/) {
	# See play.c#aszGameResult
	# See play.c#CommandDecline
	# See
	# "gnubg declines the [single game|gammon|backgammon|resignation]."
	# FIXME: get rid of gnubg prefix
	elsif ( &startsWith( $line, 'gnubg declines the ' ) ) {
		if ($resign_pending) {
			$resign_pending = 0;
			&toFibs(FIBSCMD_REJECT);
			print MATLOG "reject\n" if ($mat_log);
			$board_expected = time() + DELAY_WAITING_FOR_REPLY_TO_COMMAND;
		}

		# FIXME: Work around against a suspected bug in gnubg after
		# rejected resigns. See also case "Enter dice"
	}

	# Check if and how I should offer to resign. Numbers of interest are:
	# $1 = opponent's probability of winning this game
	# $2 = opponent's probability of winning a gammon
	# $3 = opponent's probability of winning a backgammon
	# $mwc = our percentage chance of winning the match
	# $board[$BD_ONHOME2] = number of men already borne off by the opponent
	#
	elsif ( $line =~
m/^       \d\.\d\d\d \d\.\d\d\d \d\.\d\d\d - (\d\.\d\d\d) (\d\.\d\d\d) (\d\.\d\d\d)\s*$/
	  )
	{
		if ( $1 >= 0.999 && !$resign_offered && $board[BD_ONHOME2] < 13 ) {
			if ( $3 >= 0.999 || ( $3 >= 0.010 && $mwc <= 0.01 ) ) {
				&toFibs(FIBSCMD_RESIGN_B);
				print MATLOG FIBSCMD_RESIGN_B if ($mat_log);
				$resign_offered = 1;
			}
			elsif (( $2 >= 0.999 && $3 <= 0.001 )
				|| ( $2 >= 0.010 && $mwc <= 0.01 ) )
			{
				&toFibs(FIBSCMD_RESIGN_G);
				print MATLOG FIBSCMD_RESIGN_G if ($mat_log);
				$resign_offered = 1;
			}
			elsif ( ( $2 + $3 ) <= 0.001 ) {
				&toFibs(FIBSCMD_RESIGN_N);
				print MATLOG FIBSCMD_RESIGN_N if ($mat_log);
				$resign_offered = 1;
			}
		}
	}
}

# I observed "Correct cube decision: Double, take" in response to opposing double!
# This happens with gnubg 0.13.0 (not sure about recent snapshots).
#
sub handleCubeAction($$) {
	my ( $command, $opponent_action ) = @_;
	print "DEBUG handleCubeAction board[BD_DOUBLED]="
	  . $board[BD_DOUBLED]
	  . " command='"
	  . $command
	  . "' opponent_action='"
	  . $opponent_action . "'\n";

	# Case 1: We have not been doubled, i.e. we now double ourselves (or not)
	#

	if ( !$board[BD_DOUBLED] ) {
		&toFibs($command);
		print MATLOG FIBSCMD_DOUBLE . "\n"
		  if ( $command eq FIBSCMD_DOUBLE && $mat_log );
		$board_expected = time() + DELAY_WAITING_FOR_REPLY_TO_COMMAND;
	}

# Case 2: We have to reply to a double.
# This is odd gnubg behaviour, which results from gnubg reverting to a previous
# position when it can not deal with the MatchID.
# Example:
#
# To gnubg: set gnubgid WK9TBgC1eTIGAA:cBGgAAAAAAAA
# To gnubg: hint 1
# from gnubg: SetMatchID cannot handle positions where a double has been offered.
# from gnubg: Stepping back to the offering of the cube.
# [...]
# from gnubg: Proper cube action: Double, pass
#
# board[BD_DOUBLED]=1 here, so we know we have to respond to the
# offered cube according to the recommendation gnubg gave to the opponent
# in the situation the cube was cast.
# Let's go for it ...
#

	else {
		# Accept the offered cube
		if (   &startsWith( $opponent_action, 'take' )
			|| &startsWith( $opponent_action, 'beaver' ) )
		{
			&toFibs(FIBSCMD_ACCEPT);
			print MATLOG FIBSCMD_ACCEPT . "\n" if ($mat_log);
			$board_expected = time() + DELAY_WAITING_FOR_REPLY_TO_COMMAND;

		}

		# Reject the offered cube
		elsif ( &startsWith( $opponent_action, 'pass' ) ) {
			&toFibs(FIBSCMD_REJECT);
			print MATLOG FIBSCMD_REJECT . "\n" if ($mat_log);
		}
		else {
			# FIXME: gnubg changed it's syntax. Check code.
		}
	}
}

sub handleDeadCube() {
	print "DEBUG handleDeadCube board[BD_DOUBLED]=" . $board[BD_DOUBLED] . "\n";

	&toFibs( FIBSCMD_KIBITZ,
"Cubing higher than match length will not earn you extra points. I will therefore accept this dead cube."
	);
	sleep(DELAY_BETWEEN_TWO_COMMANDS_SEND_TO_FIBS);
	&toFibs(FIBSCMD_ACCEPT);
	print MATLOG "accept\n" if ($mat_log);
	$board_expected = time() + DELAY_WAITING_FOR_REPLY_TO_COMMAND;
}

#######################################################################
#                 Debug code.                                         *
#######################################################################

sub get_load_average() {
	sysopen( my $fh, "/proc/loadavg", O_RDONLY ) or die $!;
	sysread( $fh, my $line, 255 ) or die $!;
	close($fh);
	my ($one_min_avg) = split /\s/, $line;
	return $one_min_avg * 1;
}

sub getMemByPid($) {

   # See: http://search.cpan.org/~doneill/Memory-Usage-0.201/lib/Memory/Usage.pm
	my $pid = shift;
	sysopen( my $fh, "/proc/$pid/statm", O_RDONLY ) or die $!;
	sysread( $fh, my $line, 255 ) or die $!;
	close($fh);

# from "man 5 proc" manpage;
#       /proc/[pid]/statm
#          Provides information about memory usage, measured in pages.  The
#          columns are:
#
#          size       (1) total program size
#                     (same as VmSize in /proc/[pid]/status)
#          resident   (2) resident set size
#                     (same as VmRSS in /proc/[pid]/status)
#          shared     (3) number of resident shared pages (i.e., backed by a file)
#                     (same as RssFile+RssShmem in /proc/[pid]/status)
#          text       (4) text (code)
#          lib        (5) library (unused since Linux 2.6; always 0)
#          data       (6) data + stack
#          dt         (7) dirty pages (unused since Linux 2.6; always 0)
#
# A page usually has a size of 4096 bytes, the local value can be checked with
# "getconf PAGESIZE" in shell.

	my ( $vsz, $rss, $share, $text, $lib_crap, $data, $dt_crap ) =
	  split( /\s+/, $line, 7 );

	#	return map { $_ * $page_size_in_kb } ($vsz, $rss, $share, $text, $data);
	return $vsz * 1;
}

sub my_memory_usage() {
	my $my_mem = getMemByPid($$);
	my $gnu_mem = defined($gnubg_pid) ? getMemByPid($gnubg_pid) : 0;
	return $my_mem + $gnu_mem;
}

sub dump_handler {
	my $len    = 0;
	my $curtim = time();
	my $dt     = $curtim - $last_tofibs_time;

	if ($USE_STDIN) {
		$len = length($stdin_buf);
		print "STDIN_BUF length $len\n";
	}
	$len = length($gnubg_buf);
	print "GNUBG_BUF length $len\n";
	$len = length($fibs_buf);
	print "FIBS_BUF length $len\n";

	#	print "GNUBG Last $gnubg_last\nGNUBG Buff $gnubg_buf\n";
	print
"\n\nLast to FIBS $last_tofibs_time current time $curtim delta $dt\nFIBS Buff $fibs_buf\n\n";
	exit(0);
}

sub term_handler {
	my ($sig) = @_;
	print "Handle Signal $sig\n";
	dump_handler();
}

# $SIG{TERM} = \&term_handler;
