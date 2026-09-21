<?php
// Open-HotSpot local FAS for openNDS fas_secure_enabled=1.
//
// The official level-1 contract sends ?fas=<base64 payload>. After local
// credential verification this endpoint returns the documented
// /opennds_auth/ form with tok=sha256(hid + faskey), redir, and an opaque
// custom auth transaction key. The PIN never reaches openNDS or a log.
// openNDS 10.3.1's CPD login payload may omit authdir and include gatewayurl;
// that observed shape is accepted below and still uses only the documented
// /opennds_auth/ virtual endpoint.

declare(strict_types=1);

$kdfPath = getenv('OPEN_HOTSPOT_KDF_PATH') ?: '/usr/lib/open-hotspot/kdf.php';
require_once $kdfPath;

const HOTSPOT_DB = '/etc/open-hotspot/hotspot.db';

function html(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function portal_template_name(): string
{
    $name = getenv('OPEN_HOTSPOT_TEMPLATE_NAME') ?: '';
    if ($name === '' && is_executable('/sbin/uci')) {
        $name = trim((string) shell_exec('/sbin/uci -q get open-hotspot.global.active_template 2>/dev/null'));
    }
    return in_array($name, ['english', 'arabic-rtl'], true) ? $name : 'arabic-rtl';
}

function portal_template(): string
{
    $explicit = getenv('OPEN_HOTSPOT_TEMPLATE_PATH') ?: '';
    $templateRoot = getenv('OPEN_HOTSPOT_TEMPLATE_ROOT') ?: '/usr/share/open-hotspot/templates';
    $path = $explicit !== '' ? $explicit
        : '/etc/open-hotspot/portal.html';
    if (!is_readable($path)) {
        $path = $templateRoot . '/' . portal_template_name() . '.html';
    }
    $contents = @file_get_contents($path);
    $required = ['{{CSS_HREF}}', '{{PAGE_TITLE}}', '{{BRAND}}', '{{HEADING}}', '{{ALERT}}', '{{BODY}}'];
    if (!is_string($contents) || $contents === '') {
        $contents = (string) @file_get_contents(
            $templateRoot . '/arabic-rtl.html'
        );
    }
    foreach ($required as $marker) {
        if (strpos($contents, $marker) === false) {
            $contents = (string) @file_get_contents(
                $templateRoot . '/arabic-rtl.html'
            );
            break;
        }
    }
    return $contents;
}

function portal_render(string $heading, string $body, string $message = ''): string
{
    $alert = $message === '' ? '' : '<p role="alert">' . html($message) . '</p>';
    return strtr(portal_template(), [
        '{{CSS_HREF}}' => '/nds/open-hotspot-fas.css',
        '{{PAGE_TITLE}}' => 'Open-HotSpot',
        '{{BRAND}}' => 'Open-HotSpot',
        '{{HEADING}}' => html($heading),
        '{{ALERT}}' => $alert,
        '{{BODY}}' => $body,
    ]);
}

function fail_page(string $message, int $status = 400): never
{
    http_response_code($status);
    header('Content-Type: text/html; charset=UTF-8');
    $body = '<a class="oh-button" href="http://status.client">فتح بوابة الدخول</a>';
    echo portal_render('تعذر إكمال تسجيل الدخول', $body, $message);
    exit;
}

function fas_key(): string
{
    $fromEnv = getenv('OPEN_HOTSPOT_FAS_KEY');
    if (is_string($fromEnv) && $fromEnv !== '') {
        return $fromEnv;
    }

    $uci = '/sbin/uci';
    if (is_executable($uci)) {
        $key = shell_exec($uci . ' -q get opennds.@opennds[0].faskey 2>/dev/null');
        if (is_string($key) && trim($key) !== '') {
            return trim($key);
        }
    }
    fail_page('لم يتم إعداد مفتاح FAS على الراوتر.', 503);
}

function decode_fas_payload(string $encoded): array
{
    if ($encoded === '') {
        fail_page('بيانات FAS الناقصة.');
    }
    $decoded = base64_decode($encoded, true);
    if ($decoded === false || $decoded === '') {
        fail_page('بيانات FAS غير صالحة.');
    }

    $values = [];
    foreach (explode(', ', $decoded) as $part) {
        $separator = strpos($part, '=');
        if ($separator === false) {
            continue;
        }
        $name = substr($part, 0, $separator);
        $value = substr($part, $separator + 1);
        if (preg_match('/^[A-Za-z0-9_]+$/', $name) === 1) {
            $values[$name] = $value;
        }
    }

    // The documented name is hid. Accept client_hid as a compatibility alias
    // for deployments/clients that expose the same hashed token under that
    // label, but never continue without a verified hid value.
    if (!isset($values['hid']) && isset($values['client_hid'])) {
        $values['hid'] = $values['client_hid'];
    }
    foreach (['hid', 'clientmac', 'gatewayaddress'] as $required) {
        if (!isset($values[$required]) || $values[$required] === '') {
            fail_page('بيانات FAS الناقصة.');
        }
    }
    // The installed openNDS 10.3.1 CPD flow observed on the target sends
    // gatewayurl/cpd_query but no authdir. The official FAS contract defines
    // /opennds_auth/ as the virtual authentication endpoint, so accept this
    // exact compatibility shape without accepting an arbitrary path.
    if ((!isset($values['authdir']) || $values['authdir'] === '')
        && (!isset($values['gatewayurl']) || rawurldecode($values['gatewayurl']) === '')) {
        fail_page('بيانات FAS الناقصة.');
    }
    return $values;
}

function db(): PDO
{
    $path = getenv('OPEN_HOTSPOT_DB_PATH') ?: HOTSPOT_DB;
    try {
        $pdo = new PDO('sqlite:' . $path, null, null, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_TIMEOUT => 5,
        ]);
        $pdo->exec('PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;');
        return $pdo;
    } catch (Throwable $error) {
        fail_page('قاعدة البيانات غير متاحة.', 503);
    }
}

function normalized_mac(string $mac): string
{
    $mac = strtoupper($mac);
    if (preg_match('/^[0-9A-F]{2}(:[0-9A-F]{2}){5}$/', $mac) !== 1) {
        fail_page('عنوان الجهاز غير صالح.');
    }
    return $mac;
}

function period_helper_window(string $type, ?string $renewedAt, DateTimeImmutable $now): array
{
    if (!in_array($type, ['hourly', 'daily', 'monthly', 'yearly', 'none'], true)) {
        fail_page('نوع الفترة غير صالح.');
    }
    $helper = getenv('OPEN_HOTSPOT_PERIOD_HELPER') ?: '/usr/lib/open-hotspot/period.sh';
    if (!is_readable($helper)) {
        fail_page('مساعد الفترات غير متاح.', 503);
    }
    $renewed = $renewedAt ?? '';
    $command = '/bin/sh -c ' . escapeshellarg(
        '. ' . escapeshellarg($helper) . '; period_window_effective "$1" "$2" "$3"'
    ) . ' -- ' . escapeshellarg($type) . ' ' . escapeshellarg($renewed)
        . ' ' . escapeshellarg((string) $now->format('U'));
    $output = shell_exec($command);
    if (!is_string($output)) {
        fail_page('تعذر حساب فترة الحصة.', 503);
    }
    $parts = explode("\t", trim($output));
    if (count($parts) !== 4
        || preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/', $parts[0]) !== 1
        || preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/', $parts[1]) !== 1) {
        fail_page('نتيجة الفترة غير صالحة.', 503);
    }
    return [$parts[0], $parts[1]];
}

function period_bounds(string $type, DateTimeImmutable $now): array
{
    return period_helper_window($type, null, $now);
}

function effective_period_bounds(string $type, DateTimeImmutable $now, ?string $renewedAt): array
{
    return period_helper_window($type, $renewedAt, $now);
}

function post_value(string $name): string
{
	static $parsedBody;
	if (!is_array($parsedBody)) {
		$parsedBody = $_POST;
		if ($parsedBody === [] && ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
			$body = file_get_contents('php://input');
			$parsedBody = [];
			if (is_string($body) && $body !== '') {
				parse_str($body, $parsedBody);
			}
		}
	}
	$value = $parsedBody[$name] ?? '';
    return is_string($value) ? $value : '';
}

function redeem_voucher(PDO $pdo, string $code, string $username, string $pin,
    DateTimeImmutable $now): ?array
{
    if (preg_match('/^[A-Fa-f0-9]{20}$/', $code) !== 1) {
        return null;
    }
    $iterations = 100000;
    if (is_executable('/sbin/uci')) {
        $configured = trim((string) shell_exec('/sbin/uci -q get open-hotspot.global.pin_iterations 2>/dev/null'));
        if (preg_match('/^[0-9]+$/', $configured) === 1 && (int) $configured >= 1) {
            $iterations = (int) $configured;
        }
    }
    $pdo->beginTransaction();
    try {
        $voucher = $pdo->prepare(
            'SELECT v.id, v.profile_id, v.validity_seconds, p.period_type,
                    p.time_limit_s, p.upload_limit_b, p.download_limit_b,
                    p.upload_rate_kbps, p.download_rate_kbps, p.max_devices
               FROM vouchers v JOIN profiles p ON p.id = v.profile_id
              WHERE v.code = :code AND v.status = "unused"
                AND (v.expires_at IS NULL OR julianday(v.expires_at) > julianday("now"))
              LIMIT 1'
        );
        $voucher->execute([':code' => strtoupper($code)]);
        $row = $voucher->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            $pdo->rollBack();
            return null;
        }
        $salt = bin2hex(random_bytes(16));
        $hash = open_hotspot_pbkdf2_hex($pin, $salt, $iterations);
        if ($hash === null) {
            $pdo->rollBack();
            return null;
        }
        $expiresAt = $now->modify('+' . (int) $row['validity_seconds'] . ' seconds')
            ->format('Y-m-d\TH:i:s\Z');
        $insert = $pdo->prepare(
            'INSERT INTO accounts
                (username, pin_hash, pin_salt, pin_iter, profile_id, expires_at)
             VALUES (:username, :pin_hash, :pin_salt, :pin_iter, :profile_id, :expires_at)'
        );
        $insert->execute([
            ':username' => $username,
            ':pin_hash' => $hash,
            ':pin_salt' => $salt,
            ':pin_iter' => $iterations,
            ':profile_id' => $row['profile_id'],
            ':expires_at' => $expiresAt,
        ]);
        $accountId = (int) $pdo->lastInsertId();
        $redeem = $pdo->prepare(
            'UPDATE vouchers SET status = "redeemed", redeemed_by = :account_id,
                    redeemed_at = :redeemed_at
              WHERE id = :id AND status = "unused"'
        );
        $redeem->execute([
            ':account_id' => $accountId,
            ':redeemed_at' => $now->format('Y-m-d\TH:i:s\Z'),
            ':id' => $row['id'],
        ]);
        if ($redeem->rowCount() !== 1) {
            throw new RuntimeException('voucher transition failed');
        }
        $pdo->commit();
        return [
            'id' => $accountId, 'pin_hash' => $hash, 'pin_salt' => $salt,
            'pin_iter' => $iterations, 'status' => 'active',
            'expires_at' => $expiresAt, 'profile_id' => $row['profile_id'],
            'period_type' => $row['period_type'], 'time_limit_s' => $row['time_limit_s'],
            'upload_limit_b' => $row['upload_limit_b'],
            'download_limit_b' => $row['download_limit_b'],
            'upload_rate_kbps' => $row['upload_rate_kbps'],
            'download_rate_kbps' => $row['download_rate_kbps'],
            'max_devices' => $row['max_devices'], 'failed_attempts' => 0,
            'last_failed_at' => null, 'lock_until' => null,
        ];
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        return null;
    }
}

$encoded = is_string($_GET['fas'] ?? null) ? $_GET['fas'] : post_value('fas');
$fas = decode_fas_payload($encoded);
$mac = normalized_mac($fas['clientmac']);
$authDir = isset($fas['authdir']) && $fas['authdir'] !== ''
    ? trim(rawurldecode($fas['authdir']), '/') : 'opennds_auth';
if ($authDir === '' || preg_match('~^[A-Za-z0-9_/-]+$~', $authDir) !== 1) {
    fail_page('مسار المصادقة غير صالح.');
}

$gateway = rawurldecode($fas['gatewayaddress']);
if (preg_match('/^[A-Za-z0-9.:\[\]-]+$/', $gateway) !== 1) {
    fail_page('عنوان البوابة غير صالح.');
}

$origin = rawurldecode($fas['originurl'] ?? '');
if ($origin === '' || preg_match('#^https?://#i', $origin) !== 1) {
    $origin = 'http://' . $gateway . '/';
}

$pdo = db();
$message = '';
$authKey = '';

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    $username = post_value('username');
    $pin = post_value('pin');
    $voucherCode = post_value('voucher');
    if (preg_match('/^[A-Za-z0-9_.-]{1,64}$/', $username) !== 1
        || preg_match('/^[0-9]{4,32}$/', $pin) !== 1) {
        $message = 'اسم المستخدم أو PIN غير صالح.';
    } else {
        try {
            $now = new DateTimeImmutable('now', new DateTimeZone('UTC'));
            if ($voucherCode !== '') {
                $account = redeem_voucher($pdo, $voucherCode, $username, $pin, $now);
            } else {
                $stmt = $pdo->prepare(
                    'SELECT a.id, a.pin_hash, a.pin_salt, a.pin_iter, a.status, a.expires_at,
                            a.failed_attempts, a.last_failed_at, a.lock_until,
                            a.renewed_at, a.profile_id, p.period_type, p.time_limit_s, p.upload_limit_b,
                            p.download_limit_b, p.upload_rate_kbps, p.download_rate_kbps,
                            p.max_devices
                       FROM accounts a JOIN profiles p ON p.id = a.profile_id
                      WHERE a.username = :username AND a.deleted_at IS NULL LIMIT 1'
                );
                $stmt->execute([':username' => $username]);
                $account = $stmt->fetch(PDO::FETCH_ASSOC);
            }
            $expired = $account && $account['expires_at'] !== null
                && new DateTimeImmutable($account['expires_at'], new DateTimeZone('UTC')) <= $now;
            $locked = $account && $account['lock_until'] !== null
                && new DateTimeImmutable($account['lock_until'], new DateTimeZone('UTC')) > $now;
            $validLogin = $account && !$locked && $account['status'] === 'active' && !$expired
                && open_hotspot_verify_pin(
                    $pin,
                    (string) $account['pin_hash'],
                    (string) $account['pin_salt'],
                    (int) $account['pin_iter']
                );
            if (!$validLogin) {
                if ($account && !$locked && $account['status'] === 'active' && !$expired) {
                    $failures = (int) $account['failed_attempts'] + 1;
                    $lockUntil = null;
                    if ($failures >= 5) {
                        $backoff = 30;
                        for ($attempt = 5; $attempt < $failures; $attempt++) {
                            $backoff = min(900, $backoff * 2);
                        }
                        $lockUntil = $now->modify('+' . $backoff . ' seconds')
                            ->format('Y-m-d\TH:i:s\Z');
                    }
                    $failed = $pdo->prepare(
                        'UPDATE accounts SET failed_attempts = :failed_attempts,
                                last_failed_at = :last_failed_at, lock_until = :lock_until,
                                updated_at = datetime("now") WHERE id = :id'
                    );
                    $failed->execute([
                        ':failed_attempts' => $failures,
                        ':last_failed_at' => $now->format('Y-m-d\TH:i:s\Z'),
                        ':lock_until' => $lockUntil,
                        ':id' => $account['id'],
                    ]);
                }
                $message = 'بيانات الدخول غير صحيحة.';
            } else {
                $reset = $pdo->prepare(
                    'UPDATE accounts SET failed_attempts = 0, last_failed_at = NULL,
                            lock_until = NULL, updated_at = datetime("now") WHERE id = :id'
                );
                $reset->execute([':id' => $account['id']]);
                [$periodStart, $periodEnd] = effective_period_bounds(
                    (string) $account['period_type'], $now, $account['renewed_at'] ?? null
                );
                $usage = $pdo->prepare(
                    'SELECT seconds_used, bytes_up, bytes_down FROM usage_periods
                      WHERE account_id = :account_id AND period_start = :period_start LIMIT 1'
                );
                $usage->execute([':account_id' => $account['id'], ':period_start' => $periodStart]);
                $used = $usage->fetch(PDO::FETCH_ASSOC) ?: [
                    'seconds_used' => 0, 'bytes_up' => 0, 'bytes_down' => 0,
                ];
                $remainingTime = (int) $account['time_limit_s'] > 0
                    ? max(0, (int) $account['time_limit_s'] - (int) $used['seconds_used']) : 0;
                $remainingUp = (int) $account['upload_limit_b'] > 0
                    ? max(0, (int) $account['upload_limit_b'] - (int) $used['bytes_up']) : 0;
                $remainingDown = (int) $account['download_limit_b'] > 0
                    ? max(0, (int) $account['download_limit_b'] - (int) $used['bytes_down']) : 0;
                if (($account['time_limit_s'] > 0 && $remainingTime === 0)
                    || ($account['upload_limit_b'] > 0 && $remainingUp === 0)
                    || ($account['download_limit_b'] > 0 && $remainingDown === 0)) {
                    $message = 'انتهت الحصة الحالية.';
                } else {
                    $authKey = bin2hex(random_bytes(16));
                    $snapshot = implode('|', [
                        $account['profile_id'], $remainingTime,
                        $remainingUp, $remainingDown,
                        $account['upload_rate_kbps'], $account['download_rate_kbps'],
                        $periodStart, $periodEnd,
                    ]);
                    $insert = $pdo->prepare(
                        'INSERT INTO auth_transactions
                            (auth_key, account_id, device_mac, profile_id, policy_snapshot,
                             expires_at, state)
                         VALUES (:auth_key, :account_id, :device_mac, :profile_id,
                             :policy_snapshot, datetime("now", "+15 minutes"), "pending")'
                    );
                    $insert->execute([
                        ':auth_key' => $authKey,
                        ':account_id' => $account['id'],
                        ':device_mac' => $mac,
                        ':profile_id' => $account['profile_id'],
                        ':policy_snapshot' => $snapshot,
                    ]);
                }
            }
        } catch (Throwable $error) {
            $message = 'تعذر التحقق من بيانات الدخول.';
        }
    }
}

$self = $_SERVER['SCRIPT_NAME'] ?? '/nds/fas.php';
$postAction = $self . '?fas=' . rawurlencode($encoded);
header('Content-Type: text/html; charset=UTF-8');
$body = '';
if ($authKey !== '') {
    $token = hash('sha256', $fas['hid'] . fas_key());
    $authAction = 'http://' . $gateway . '/' . $authDir . '/';
    $body .= '<form method="get" action="' . html($authAction) . '">';
    $body .= '<input type="hidden" name="tok" value="' . html($token) . '">';
    $body .= '<input type="hidden" name="custom" value="' . html($authKey) . '">';
    $body .= '<input type="hidden" name="redir" value="' . html($origin) . '">';
    $body .= '<button class="oh-button" type="submit">متابعة</button></form>';
} else {
    $body .= '<form class="oh-login-form" method="post" action="' . html($postAction) . '">';
    $body .= '<label>اسم المستخدم <input name="username" required maxlength="64" autocomplete="username"></label>';
    $body .= '<label>PIN <input name="pin" required inputmode="numeric" type="password" maxlength="32" autocomplete="current-password"></label>';
    $body .= '<label>رمز الباقة (اختياري) <input name="voucher" inputmode="text" maxlength="20" autocomplete="off"></label>';
    $body .= '<small>عند استخدام رمز جديد سيتم إنشاء الحساب وربطه بالباقة تلقائيًا.</small>';
    $body .= '<input type="hidden" name="fas" value="' . html($encoded) . '">';
    $body .= '<button class="oh-button" type="submit">دخول</button></form>';
}
echo portal_render('تسجيل الدخول إلى الشبكة', $body, $message);
