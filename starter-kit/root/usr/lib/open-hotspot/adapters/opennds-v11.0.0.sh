#!/bin/sh
# Versioned openNDS adapter contract: current target baseline.

OPEN_HOTSPOT_ADAPTER_ID='opennds-v11.0.0'
OPEN_HOTSPOT_ADAPTER_FAS='local-level1-status-client'
OPEN_HOTSPOT_ADAPTER_BINAUTH='seven-argument-callback'

opennds_adapter_contract_selftest() {
	[ "$OPEN_HOTSPOT_ADAPTER_ID" = opennds-v11.0.0 ]
}
