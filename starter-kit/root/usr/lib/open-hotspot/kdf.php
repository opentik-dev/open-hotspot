<?php
// Shared PBKDF2-HMAC-SHA256 implementation for the local FAS and CLI helper.
// The target exposes hash_pbkdf2 through PHP's hash extension, but not the
// OpenSSL PHP module. Keep the accepted verifier format deliberately narrow.

function open_hotspot_pbkdf2_hex(string $pin, string $salt, int $iterations): ?string
{
    if (!function_exists('hash_pbkdf2') || !function_exists('preg_match')) {
        return null;
    }
    if ($iterations < 1 || $iterations > 10000000) {
        return null;
    }

    $result = hash_pbkdf2('sha256', $pin, $salt, $iterations, 64, false);
    return is_string($result) && preg_match('/^[0-9a-f]{64}$/', $result) === 1
        ? $result
        : null;
}

function open_hotspot_verify_pin(
    string $pin,
    string $storedHash,
    string $salt,
    int $iterations
): bool {
    $candidate = open_hotspot_pbkdf2_hex($pin, $salt, $iterations);
    return $candidate !== null && hash_equals($storedHash, $candidate);
}
