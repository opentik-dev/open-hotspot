#!/bin/sh
# Versioned openNDS adapter contract: rollback baseline.

OPEN_HOTSPOT_ADAPTER_ID='opennds-v10.3.1-r3'
OPEN_HOTSPOT_ADAPTER_FAS='legacy-target-contract'
OPEN_HOTSPOT_ADAPTER_BINAUTH='seven-argument-callback'

opennds_adapter_contract_selftest() {
	[ "$OPEN_HOTSPOT_ADAPTER_ID" = opennds-v10.3.1-r3 ]
}
