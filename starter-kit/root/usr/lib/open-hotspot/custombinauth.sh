#!/bin/sh
# Installed later as /usr/lib/opennds/custombinauth.sh. The stock
# /usr/lib/opennds/binauth_log.sh remains in place so auth_restore is retained.

. /usr/lib/open-hotspot/binauth.sh
open_hotspot_binauth_apply "$@"
