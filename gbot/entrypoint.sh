#!/bin/sh

echo Version 2.1 20261009 No Vault
echo "Image w2vy/gammonbot:${GBOT_VERSION} commit ${GBOT_COMMIT} built ${GBOT_BUILT}"

GBOT_DIR=/home/gammonbot/

####
# Credentials
####

if [ -z "${BOT_PASSWD}" ]; then
  echo "BOT_PASSWD Not defined in app config"
  exit 12
else
  printf "\$BOTPASS='${BOT_PASSWD}';\nreturn 1;\n" >> "${GBOT_DIR}/config.defaults.pl"
fi

####
# Standalone test bot
####

if [ -n "${BOT_ID}" ]; then
  echo "Running standalone test bot ${BOT_ID} on fibs"
  perl "${GBOT_DIR}/gammonbot.pl" "${BOT_ID}" "${BOT_PASSWD}"
  exit 0
fi

####
# Orchestration of multiple bots
####

if [ -z "${LOCK_PASSWD}" ]; then
  echo "LOCK_PASSWD Not defined in app config"
  exit 11
fi

if [ -f "${GBOT_DIR}/botlist.pl" ]; then
  printf "\$LOCK_PASSWD='${LOCK_PASSWD}';\nreturn 1;\n" >> "${GBOT_DIR}/botlist.pl"
else
  echo "botlist.pl not located"
  exit 13
fi

for day in 0 1 2 3 4 5 6; do
  if [ -f "${GBOT_DIR}/botlist-${day}.pl" ]; then
    printf "\$LOCK_PASSWD='${LOCK_PASSWD}';\nreturn 1;\n" >> "${GBOT_DIR}/botlist-${day}.pl"
  fi
done

${GBOT_DIR}/check_bot