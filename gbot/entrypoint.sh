#!/bin/sh

echo Vault $VAULT_DNS Port $FLUX_PORT

rm -f FluxVault.py

wget https://raw.githubusercontent.com/w2vy/FluxVault/main/FluxVault.py
chmod +x FluxVault.py

/home/gammonbot/check_bot&

python3 FluxVault.py Node $FLUX_PORT $VAULT_DNS botlist.pl

