#!/bin/sh

open_hotspot_preflight() {
	: > "${MOCK_PREFLIGHT_MARKER:?MOCK_PREFLIGHT_MARKER is required}"
	printf '%s\n' 'opennds_version=mock-10.3.1'
	printf '%s\n' 'dnsmasq_full=not-required-by-core-plan'
}
