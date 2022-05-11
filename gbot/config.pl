#!/usr/bin/perl

#######################################################################
#            The following are customizable parameters.               *
#######################################################################

# True if we want to log everything, false to be quiet
$DO_PRINT = 0;

# Maintance mode, only allow admins to play if true
$maint_mode = 0;

#######################################################################
#                 End of customizable parameters.                     *
#######################################################################

# Now include other files needed to complete config

if ($BOTID =~ m/^BlunderBot/ ) {
  require "blunderer.pl";
} else {
    require "worldclass.pl";
}

require "banned.pl";

return 1;
