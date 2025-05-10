#!/usr/bin/perl

#######################################################################
#            The following are customizable parameters.               *
#            These are the global defaults, DO NOT CHANGE             *
#######################################################################

# The FIBS login names of the bot administrators. The bot treats chat
# messages from this persons specially.  Telling the bot "last" will
# cause it to terminate at the end of its current match.  Any other
# message, such as "bye", will be sent to FIBS as a command.
#

$LOCK_NAME = "botLock";
$DEBUG = 0;

@BOT_NAMES = qw(
BlunderBot_XI
BlunderBot_VI
BlunderBot_III
BlunderBot_X
GammonBot_V
GammonBot_VII
GammonBot
GammonBot_XII
GammonBot_XVI
);

#######################################################################
#                 End of customizable parameters.                     *
#######################################################################
#return 1;
