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


  # "World Class" play level:
 "set evaluation chequer eval plies 2",
 "set evaluation chequer eval cubeful on",
 "set evaluation cubedecision eval plies 2",
 "set evaluation cubedecision eval cubeful on",
 "set analysis chequer eval plies 2",
 "set analysis chequer eval cubeful on",
 "set analysis cubedecision eval plies 2",
 "set analysis cubedecision eval cubeful on",
 "set evaluation movefilter 1 0  0 8 0.160000",
 "set evaluation movefilter 2 0  0 8 0.160000",
 "set evaluation movefilter 2 1 -1 0 0.000000",
 "set evaluation movefilter 3 0  0 8 0.160000",
 "set evaluation movefilter 3 1 -1 0 0.000000",
 "set evaluation movefilter 3 2  0 2 0.040000",
 "set evaluation movefilter 4 0  0 8 0.160000",
 "set evaluation movefilter 4 1 -1 0 0.000000",
 "set evaluation movefilter 4 2  0 2 0.040000",
 "set evaluation movefilter 4 3 -1 0 0.000000",
 "set analysis movefilter 1 0  0 8 0.160000",
 "set analysis movefilter 2 0  0 8 0.160000",
 "set analysis movefilter 2 1 -1 0 0.000000",
 "set analysis movefilter 3 0  0 8 0.160000",
 "set analysis movefilter 3 1 -1 0 0.000000",
 "set analysis movefilter 3 2  0 2 0.040000",
 "set analysis movefilter 4 0  0 8 0.160000",
 "set analysis movefilter 4 1 -1 0 0.000000",
 "set analysis movefilter 4 2  0 2 0.040000",
 "set analysis movefilter 4 3 -1 0 0.000000"
);

# $MIN_RATING = 1400;
# $LOW_RATING = 1300;
# $LOW_RATING_LEN = 5;

#######################################################################
#                 End of customizable parameters.                     *
#######################################################################

