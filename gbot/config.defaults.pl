#!/usr/bin/perl

#######################################################################
#            The following are customizable parameters.               *
#            These are the global defaults, DO NOT CHANGE             *
#######################################################################

# Location of the installed gnubg binary.
#
#$PATH_TO_GNUBG = "G_SLICE=always-malloc valgrind --leak-check=yes /home/gammonbot/gnubg/bin/gnubg-debug/bin/gnubg";
#$PATH_TO_GNUBG = "/home/gammonbot/gnubg/bin/gnubg-1.06.002-gcc-8.2.0-20190202/bin/gnubg"; 
$PATH_TO_GNUBG = "/gnubg/install/bin/gnubg"; 

# Maintance mode, only allow admins to play if true
$maint_mode = 0;

# The FIBS login names of the bot administrators. The bot treats chat
# messages from this persons specially.  Telling the bot "last" will
# cause it to terminate at the end of its current match.  Any other
# message, such as "bye", will be sent to FIBS as a command.
#
@ADMIN_LOGINS = qw(
inim
Tom
openfibs
tam
Patti
FIBSAdmin
BlunderBot_X
BlunderBot_XI
BlunderBot_XII
GammonBot_X
GammonBot_XI
GammonBot_XII
BlunderBot
BlunderBot_II
BlunderBot_III
BlunderBot_IV
BlunderBot_V
BlunderBot_VI
BlunderBot_VII
BlunderBot_VIII
BlunderBot_IX
BlunderBot_X
BlunderBot_XI
BlunderBot_XII
GammonBot
GammonBot_II
GammonBot_III
GammonBot_IV
GammonBot_V
GammonBot_VI
GammonBot_VII
GammonBot_VIII
GammonBot_IX
GammonBot_X
GammonBot_XI
GammonBot_XII
GammonBot_XIII
GammonBot_XIV
GammonBot_XV
GammonBot_XVI
GammonBot_XVII
GammonBot_XVIII
GammonBot_XIX
GammonBot_XX
);

# The administrator's email address.  Be sure to escape the @.
# This is the person to receive trouble reports.
#

$ADMIN_EMAIL = "bots\@moulton.us";

# Base file name used to stats file on dice (and maybe other things)
#$file_base = "dice/" . $BOTID . "_";

# The User's home directory for data storage
# this is set when a match is started
#$user_base = "data/player/";


# Log all I/O to a single file
$log_file = "botlog.txt";

$do_fibs_log = 0;

# True if we want to log everything, false to be quiet

$DO_PRINT = 0;

# True if we want to use stdin for 'last' command as well

$USE_STDIN = 0;

# The array of greetings when starting a new match.  There may be as
# many of these as you like.  Do not remove the plug for ParlorPlay!
#
@INITIAL_GREETINGS = (
	"Hi, I am a computer program. Enjoy your match. If I stop responding, please send the respective command 'move', 'join', or 'roll' in kibitz.",
	"I am running from all over the world on the decentralized Flux network, see http://RunonFlux.io"
# "Visit www.parlorplay.com for a nice browser interface to FIBS, or to learn about me.",
# "Visit www.fibsboard.com and share your FIBS experiences.",
# "Kibitz move or roll if i stop responding.",
# "Please do not complain about the dice - The *only* place they can come from is FIBS period!!!",
);

# This is our standard reply when someone does a say or tell to us.
# Feel free to change this to whatever you like.
#
$TELL_REPLY = "Hi! I may be a decent backgammon player, but my chat skills are far below human. So stop buggin me!";

# Maximum length of a match that we are willing to play.
#
$MAX_MATCH_LENGTH = 13;

# Players who have this many (or more) saved games will be refused.
#
$MAX_SAVED_GAMES = 10;

# I am cleaning up my OWN saved games
#

$CLEANUP_SAVED = 0;

# If the bot is allowed to play unlimited matches (1=yes, 0=no).
#
$UNLIMITED_ALLOWED = 0;

# How long we wait for players to resume matches after our last match
#
# $RESUME_DELAY = 20;

# Minimum wait time in seconds between matches against the same person.
# This keeps players from hogging the bot.
#
# $MATCH_DELAY = $RESUME_DELAY + 30;
# $MATCH_DELAY = 0;

# The FIBS server host we want to connect to.
$FIBS_SERVER_HOST = "fibs.com";

# The FIBS server host's port we want to connect to.
$FIBS_SERVER_PORT = 4321;

#$MIN_RATING = 3000;
#$LOW_RATING = 900;
#$LOW_RATING_LEN = 13;

#######################################################################
#                 End of customizable parameters.                     *
#######################################################################
#return 1;
