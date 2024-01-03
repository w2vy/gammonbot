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

/home/gammonbot/check_bot

