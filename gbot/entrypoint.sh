#!/bin/sh

echo Version 1.1 8/24/2022 Vault $VAULT_DNS Port $FLUX_PORT

rm -f botlist.pl

git clone https://github.com/RunOnFlux/FluxVault.git
cd FluxVault
git checkout python_class
cd ..
pip3 install ./FluxVault

(echo "* * * * * /home/gammonbot/cron_bot" ; crontab -l)| crontab -

crond

python3 gbot_node.py
