<?php
// Import the pre-r112 Open-HotSpot database into schema v6.
// Legacy plaintext credentials are read only on the target and replaced by PBKDF2.
declare(strict_types=1);

function fail(string $message): never
{
    $stream = fopen('php://stderr', 'wb');
    if ($stream !== false) fwrite($stream, "open-hotspot legacy import: {$message}\n");
    exit(1);
}
function intOrZero(mixed $value): int
{
    if ($value === null || $value === '') return 0;
    if (!preg_match('/^[0-9]+$/', (string) $value)) fail('legacy numeric field is invalid');
    return (int) $value;
}
function bytesFromKb(mixed $value): string
{
    $text = (string) ($value ?? '0');
    if ($text === '') $text = '0';
    if (!preg_match('/^[0-9]+$/', $text)) fail('legacy quota is invalid');
    $carry = 0; $out = '';
    for ($i = strlen($text) - 1; $i >= 0; $i--) {
        $product = ((int) $text[$i] * 1024) + $carry;
        $out = (string) ($product % 10) . $out;
        $carry = intdiv($product, 10);
    }
    while ($carry > 0) { $out = (string) ($carry % 10) . $out; $carry = intdiv($carry, 10); }
    $out = ltrim($out, '0');
    return $out === '' ? '0' : $out;
}
function safeName(string $name, int $id): string
{
    $name = trim($name);
    return $name === '' ? 'legacy-' . $id : $name;
}
function hashLegacyPassword(string $password): array
{
    $salt = bin2hex(random_bytes(16));
    $iterations = 100000;
    $hash = hash_pbkdf2('sha256', $password, $salt, $iterations, 64, false);
    if (!is_string($hash) || !preg_match('/^[0-9a-f]{64}$/', $hash)) fail('PBKDF2 derivation failed');
    return [$hash, $salt, $iterations];
}

$legacyPath = getenv('OPEN_HOTSPOT_LEGACY_DB') ?: '/etc/open-hotspot/hotspot.db';
$targetPath = getenv('OPEN_HOTSPOT_IMPORT_DB') ?: '/etc/open-hotspot/hotspot.db';
$schemaPath = getenv('OPEN_HOTSPOT_SCHEMA_PATH') ?: '/usr/lib/open-hotspot/schema.sql';
$mode = getenv('OPEN_HOTSPOT_LEGACY_IMPORT_MODE') ?: 'dry-run';
$backupPath = getenv('OPEN_HOTSPOT_LEGACY_BACKUP') ?: ($targetPath . '.r60-legacy');
if (!in_array($mode, ['dry-run', 'import'], true)) fail('mode must be dry-run or import');
if (!is_file($legacyPath) || !is_readable($legacyPath)) fail('legacy database is not readable');
if (!is_file($schemaPath) || !is_readable($schemaPath)) fail('schema is not readable');

$legacy = new PDO('sqlite:' . $legacyPath, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
$legacy->exec('PRAGMA query_only=ON');
$tableNames = $legacy->query("SELECT name FROM sqlite_master WHERE type='table'")?->fetchAll(PDO::FETCH_COLUMN) ?: [];
foreach (['users', 'profiles', 'devices', 'quota_usage', 'user_quota_policies'] as $table) {
    if (!in_array($table, $tableNames, true)) fail('legacy database is missing table ' . $table);
}
$users = $legacy->query('SELECT id, username, password, profile_id, status FROM users ORDER BY id')->fetchAll(PDO::FETCH_ASSOC);
$profiles = [];
foreach ($legacy->query('SELECT id, name, download_rate, upload_rate, download_quota, session_timeout, max_devices FROM profiles')->fetchAll(PDO::FETCH_ASSOC) as $row) $profiles[(int) $row['id']] = $row;
$policies = [];
foreach ($legacy->query('SELECT user_id, download_rate_kbit, upload_rate_kbit, download_quota_kb, upload_quota_kb, session_timeout_min, period_type, max_devices FROM user_quota_policies')->fetchAll(PDO::FETCH_ASSOC) as $row) $policies[(int) $row['user_id']] = $row;
$devices = $legacy->query('SELECT user_id, mac_address, created_at FROM devices ORDER BY id')->fetchAll(PDO::FETCH_ASSOC);
$usage = $legacy->query('SELECT user_id, period_key, period_start, period_end, download_used_kb, upload_used_kb FROM quota_usage')->fetchAll(PDO::FETCH_ASSOC);
$counts = ['users' => count($users), 'profiles' => count($profiles), 'devices' => count($devices), 'usage_periods' => count($usage), 'skipped_devices' => 0];
if ($mode === 'dry-run') {
    foreach ($devices as $device) {
        $mac = strtoupper(trim((string) ($device['mac_address'] ?? '')));
        if (!preg_match('/^[0-9A-F]{2}(?::[0-9A-F]{2}){5}$/', $mac)) $counts['skipped_devices']++;
    }
    printf("legacy-import dry-run users=%d profiles=%d devices=%d usage_periods=%d skipped_devices=%d\n", $counts['users'], $counts['profiles'], $counts['devices'], $counts['usage_periods'], $counts['skipped_devices']);
    exit(0);
}
if (getenv('OPEN_HOTSPOT_LEGACY_IMPORT_CONFIRM') !== 'YES') fail('import requires OPEN_HOTSPOT_LEGACY_IMPORT_CONFIRM=YES');
$targetDir = dirname($targetPath);
if (!is_dir($targetDir) && !mkdir($targetDir, 0700, true)) fail('cannot create target directory');
$tmpPath = $targetPath . '.import.' . getmypid();
@unlink($tmpPath);
try {
    $new = new PDO('sqlite:' . $tmpPath, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    $schema = file_get_contents($schemaPath);
    if ($schema === false || $new->exec($schema) === false) fail('cannot initialize imported schema');
    $new->exec('PRAGMA foreign_keys=ON');
    $new->beginTransaction();
    $profileIds = [];
    $profileInsert = $new->prepare('INSERT INTO profiles (name, period_type, time_limit_s, upload_limit_b, download_limit_b, upload_rate_kbps, download_rate_kbps, max_devices) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
    foreach ($profiles as $oldId => $profile) {
        $profileInsert->execute([safeName((string) ($profile['name'] ?? ''), $oldId), 'none', intOrZero($profile['session_timeout'] ?? 0) * 60, bytesFromKb($profile['download_quota'] ?? 0), bytesFromKb($profile['download_quota'] ?? 0), intOrZero($profile['upload_rate'] ?? 0), intOrZero($profile['download_rate'] ?? 0), max(1, intOrZero($profile['max_devices'] ?? 1))]);
        $profileIds[$oldId] = (int) $new->lastInsertId();
    }
    if ($profileIds === []) { $profileInsert->execute(['legacy-default', 'none', 0, 0, 0, 0, 0, 1]); $profileIds[0] = (int) $new->lastInsertId(); }
    $accountIds = [];
    $accountInsert = $new->prepare('INSERT INTO accounts (username, pin_hash, pin_salt, pin_iter, profile_id, status) VALUES (?, ?, ?, ?, ?, ?)');
    foreach ($users as $user) {
        $id = (int) $user['id'];
        if (isset($policies[$id])) {
            $policy = $policies[$id];
            $period = in_array((string) ($policy['period_type'] ?? ''), ['hourly', 'daily', 'monthly', 'yearly', 'none'], true) ? (string) $policy['period_type'] : 'none';
            $profileInsert->execute(['legacy-user-' . $id, $period, intOrZero($policy['session_timeout_min'] ?? 0) * 60, bytesFromKb($policy['upload_quota_kb'] ?? 0), bytesFromKb($policy['download_quota_kb'] ?? 0), intOrZero($policy['upload_rate_kbit'] ?? 0), intOrZero($policy['download_rate_kbit'] ?? 0), max(1, intOrZero($policy['max_devices'] ?? 1))]);
            $profileIds[$id] = (int) $new->lastInsertId();
        }
        $oldProfile = (int) ($user['profile_id'] ?? 0);
        $profileId = $profileIds[$id] ?? $profileIds[$oldProfile] ?? reset($profileIds);
        [$hash, $salt, $iterations] = hashLegacyPassword((string) ($user['password'] ?? ''));
        $status = ((string) ($user['status'] ?? 'active') === 'suspended') ? 'suspended' : 'active';
        $accountInsert->execute([safeName((string) $user['username'], $id), $hash, $salt, $iterations, $profileId, $status]);
        $accountIds[$id] = (int) $new->lastInsertId();
    }
    $deviceInsert = $new->prepare('INSERT OR IGNORE INTO devices (account_id, mac, created_at, last_seen) VALUES (?, ?, ?, datetime("now"))');
    foreach ($devices as $device) {
        $mac = strtoupper(trim((string) ($device['mac_address'] ?? ''))); $userId = (int) ($device['user_id'] ?? 0);
        if (!isset($accountIds[$userId]) || !preg_match('/^[0-9A-F]{2}(?::[0-9A-F]{2}){5}$/', $mac)) continue;
        $deviceInsert->execute([$accountIds[$userId], $mac, $device['created_at'] ?: gmdate('Y-m-d H:i:s')]);
    }
    $usageInsert = $new->prepare('INSERT OR IGNORE INTO usage_periods (account_id, period_start, period_end, bytes_up, bytes_down) VALUES (?, ?, ?, ?, ?)');
    foreach ($usage as $row) {
        $userId = (int) ($row['user_id'] ?? 0); if (!isset($accountIds[$userId])) continue;
        $start = (string) ($row['period_start'] ?: $row['period_key']); $end = (string) ($row['period_end'] ?: $start);
        $usageInsert->execute([$accountIds[$userId], $start, $end, bytesFromKb($row['upload_used_kb'] ?? 0), bytesFromKb($row['download_used_kb'] ?? 0)]);
    }
    $new->commit();
    // schema.sql enables WAL for normal operation. Before an atomic rename,
    // fold WAL pages into the main file and switch the temporary DB to a
    // portable journal so no sidecar file is lost during installation.
    $new->exec('PRAGMA wal_checkpoint(FULL)');
    $new->exec('PRAGMA journal_mode=DELETE');
    $new = null;
    @unlink($tmpPath . '-wal'); @unlink($tmpPath . '-shm');
    chmod($tmpPath, 0600);
    if (is_file($backupPath)) fail('legacy backup path already exists; refusing overwrite');
    if (!copy($legacyPath, $backupPath)) fail('could not preserve legacy database');
    chmod($backupPath, 0600);
    if (!rename($tmpPath, $targetPath)) fail('could not atomically install imported database');
    printf("legacy-import complete users=%d profiles=%d devices=%d usage_periods=%d skipped_devices=%d\n", $counts['users'], $counts['profiles'], $counts['devices'], $counts['usage_periods'], $counts['skipped_devices']);
} catch (Throwable $e) {
    if (isset($new) && $new instanceof PDO && $new->inTransaction()) $new->rollBack();
    @unlink($tmpPath);
    if (getenv('OPEN_HOTSPOT_LEGACY_IMPORT_DEBUG') === '1') fail('import aborted: ' . $e->getMessage());
    fail('import aborted; legacy database was not changed');
}
