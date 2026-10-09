#!/bin/sh
# Compatibility bridge for the openNDS 11.0.0 OpenWrt packaging mismatch.
# The stock binauth dispatcher sources this file, so this bridge must also be
# source-compatible. `exec` would replace the dispatcher before it reaches
# custombinauth.sh and would leave the manager auth transaction pending.
. /usr/lib/opennds/check_reauth_interval.sh "$@"
