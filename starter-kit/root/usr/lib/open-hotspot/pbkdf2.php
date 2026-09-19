<?php
// stdin protocol: PIN, salt, decimal iteration count; stdout: 64 hex chars.
// The shell wrapper intentionally avoids placing the PIN in process argv.
require_once __DIR__ . '/kdf.php';

$lines = file('php://stdin', FILE_IGNORE_NEW_LINES);
if ($lines === false || count($lines) < 3) {
    exit(1);
}

$pin = $lines[0];
$salt = $lines[1];
$iterationText = $lines[2];
if (preg_match('/^[0-9]+$/', $iterationText) !== 1) {
    exit(1);
}

$iterations = (int) $iterationText;
$result = open_hotspot_pbkdf2_hex($pin, $salt, $iterations);
if ($result === null) {
    exit(1);
}

echo $result, "\n";
