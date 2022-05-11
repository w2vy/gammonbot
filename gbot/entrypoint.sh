#!/bin/sh

wget https://raw.githubusercontent.com/w2vy/FluxVault/main/FluxVault.py
chmod +x FluxVault.py
./FluxVault.py Node $FLUX_PORT $VAULT_DNS botlist.pl&

/home/gammonbot/check_bot
