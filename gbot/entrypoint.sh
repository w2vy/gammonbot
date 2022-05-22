#!/bin/sh

echo Vault $VAULT_DNS Port $FLUX_PORT

rm -f FluxVault.py
rm -f botlist.pl

wget https://raw.githubusercontent.com/w2vy/FluxVault/main/FluxVault.py
chmod +x FluxVault.py

(echo "* * * * * /home/gammonbot/cron_bot" ; crontab -l)| crontab -
crontab -l
crond

python3 FluxVault.py Node $FLUX_PORT $VAULT_DNS botlist.pl
