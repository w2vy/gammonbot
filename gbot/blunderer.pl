#!/usr/bin/perl
#######################################################################
#            The following are customizable parameters.               *
#######################################################################

# These strings are sent to gnubg for startup initialization.
# Do not change the first 4 lines.
#
@GNUBG_SETUP = (
  "set lang C",
  "set player 0 name gnubg",
  "set player 1 name opp",
  "set confirm new off",
  "set output rawboard on",
  "set rng manual",
  "set display on",
  "set automatic game off",
# TODO  "set cache 0",

  # "blunderer" play level:
  # This is half way between "advanced" (0.015) and "intermediate" (0.04)
  # I found that changing the 3rd digit must be used for fine tuning, if you
  # do 0.03 or 0.04 you end up in 1400 land already.
  # These settings are expected to place the bot around 1650 on fibs, but 
  # the experiment is ongoing still. But it seems we at least hit the 16xx
  # corridor now. 

 "set evaluation chequer eval plies 0",
 "set evaluation cubedecision eval plies 0",
 "set analysis chequer eval plies 0",
 "set analysis cubedecision eval plies 0",
  
 "set analysis chequer eval cubeful on",
 "set analysis chequer eval noise 0.025",
 "set analysis cubedecision eval cubeful on",
 "set analysis cubedecision eval noise 0.025",
 "set evaluation chequer eval cubeful on",
 "set evaluation chequer eval noise 0.025",
 "set evaluation cubedecision eval cubeful on",
 "set evaluation cubedecision eval noise 0.025",

);

# $MIN_RATING = 1000;
# $LOW_RATING = 1400;
# $LOW_RATING_LEN = 5;

#######################################################################
#                 End of customizable parameters.                     *
#######################################################################
