#!/bin/sh

echo Version 2.0 1/2/2023 No Vault

if [[ -z "${LOCK_PASSWD}" ]]; then
  echo "LOCK_PASSWD Not defined in app config"
  exit 11
fi

if [[ -z "${BOT_PASSWD}" ]]; then
  echo "BOT_PASSWD Not defined in app config"
  exit 12
fi

if [[ -f "botlist.pl" ]]; then
  echo "\$LOCK_PASSWD=\"$LOCK_PASSWD\";" >> botlist.pl
  echo "\$BOTPASS=\"$BOT_PASSWD\";" >> config.defaults.pl
  echo "return 1;" >> config.defaults.pl
else
  echo "botlist.pl not located"
  exit 13
fi
if [[ -f "botlist-0.pl" ]]; then
  echo "\$LOCK_PASSWD=\"$LOCK_PASSWD\";" >> botlist-0.pl
fi
if [[ -f "botlist-1.pl" ]]; then
  echo "\$LOCK_PASSWD=\"$LOCK_PASSWD\";" >> botlist-1.pl
fi
if [[ -f "botlist-2.pl" ]]; then
  echo "\$LOCK_PASSWD=\"$LOCK_PASSWD\";" >> botlist-2.pl
fi
if [[ -f "botlist-3.pl" ]]; then
  echo "\$LOCK_PASSWD=\"$LOCK_PASSWD\";" >> botlist-3.pl
fi
if [[ -f "botlist-4.pl" ]]; then
  echo "\$LOCK_PASSWD=\"$LOCK_PASSWD\";" >> botlist-4.pl
fi
if [[ -f "botlist-5.pl" ]]; then
  echo "\$LOCK_PASSWD=\"$LOCK_PASSWD\";" >> botlist-5.pl
fi
if [[ -f "botlist-6.pl" ]]; then
  echo "\$LOCK_PASSWD=\"$LOCK_PASSWD\";" >> botlist-6.pl
fi

/home/gammonbot/check_bot

