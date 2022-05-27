#!/bin/sh

echo Vault $VAULT_DNS Port $FLUX_PORT

rm -f FluxVault.py
rm -f botlist.pl

wget https://raw.githubusercontent.com/RunOnFlux/FluxVault/main/FluxVault.py
chmod +x FluxVault.py

(echo "* * * * * /home/gammonbot/cron_bot" ; crontab -l)| crontab -

crond

python3 FluxVault.py Node --port $FLUX_PORT --vault $VAULT_DNS botlist.pl
