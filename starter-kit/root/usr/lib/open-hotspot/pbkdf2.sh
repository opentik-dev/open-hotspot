#!/bin/sh
# pbkdf2.sh — PBKDF2-HMAC-SHA256 using the verified target PHP hash API.
#
# The target has php8-cgi/hash_pbkdf2 but does not ship the openssl CLI or the
# PHP OpenSSL module. PINs are sent to the helper over stdin, never as process
# arguments. If the helper is unavailable, hashing fails closed.

DEFAULT_ITER=100000
PBKDF2_HELPER="${OPEN_HOTSPOT_PBKDF2_HELPER:-/usr/lib/open-hotspot/pbkdf2.php}"
PBKDF2_PHP_BIN="${OPEN_HOTSPOT_PHP_BIN:-php8-cgi}"

_random_hex() {
	hexdump -v -n 16 -e '1/1 "%02x"' /dev/urandom 2>/dev/null
}

_pbkdf2_hex() {
	pin="$1"; salt="$2"; iter="$3"
	[ -r "$PBKDF2_HELPER" ] || return 1
	printf '%s\n%s\n%s\n' "$pin" "$salt" "$iter" \
		| "$PBKDF2_PHP_BIN" -q -f "$PBKDF2_HELPER" 2>/dev/null \
		| sed -n '1p'
}

# pw_hash <pin> [iterations] -> prints "pbkdf2:salt:iter:hash"
pw_hash() {
	pin="$1"
	salt=$(_random_hex) || return 1
	[ "${#salt}" -eq 32 ] || return 1
	iter="${2:-$DEFAULT_ITER}"
	case "$iter" in ''|*[!0-9]*) return 1 ;; esac
	out=$(_pbkdf2_hex "$pin" "$salt" "$iter") || return 1
	[ "${#out}" -eq 64 ] || return 1
	printf 'pbkdf2:%s:%s:%s\n' "$salt" "$iter" "$out"
}

# pw_verify <pin> <stored "pbkdf2:salt:iter:hash"> -> exit 0 if it matches
pw_verify() {
	pin="$1"; stored="$2"
	algo=$(printf '%s' "$stored" | cut -d: -f1)
	salt=$(printf '%s' "$stored" | cut -d: -f2)
	iter=$(printf '%s' "$stored" | cut -d: -f3)
	hash=$(printf '%s' "$stored" | cut -d: -f4)
	[ "$algo" = pbkdf2 ] || return 1
	case "$iter:$salt:$hash" in
		*[!A-Za-z0-9:]*|:*|*::*) return 1 ;;
	esac
	candidate=$(_pbkdf2_hex "$pin" "$salt" "$iter") || return 1
	[ "${#candidate}" -eq 64 ] && [ "$candidate" = "$hash" ]
}
