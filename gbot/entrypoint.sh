#!/bin/sh

wget https://github.com/w2vy/FluxVault/blob/main/FluxVault.py
chmod +x FluxVault.py
./FluxVault.py Node $FLUX_PORT $VAULT_DNS botlist.pl&

/home/gammonbot/check_bot
