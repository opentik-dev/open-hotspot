#!/bin/sh

db_init() {
	: > "${MOCK_DB_MARKER:?MOCK_DB_MARKER is required}"
}
