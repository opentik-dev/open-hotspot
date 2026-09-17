<?php
// Open-HotSpot local FAS for openNDS fas_secure_enabled=1.
//
// The official level-1 contract sends ?fas=<base64 payload>. After local
// credential verification this endpoint returns the documented
// /opennds_auth/ form with tok=sha256(hid + faskey), redir, and an opaque
// custom auth transaction key. The PIN never reaches openNDS or a log.

declare(strict_types=1);

$kdfPath = getenv('OPEN_HOTSPOT_KDF_PATH') ?: '/usr/lib/open-hotspot/kdf.php';
require_once $kdfPath;

const HOTSPOT_DB = '/etc/open-hotspot/hotspot.db';

function html(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function fail_page(string $message, int $status = 400): never
{
    http_response_code($status);
    header('Content-Type: text/html; charset=UTF-8');
    echo '<!doctype html><html lang="ar" dir="rtl"><meta charset="UTF-8">';
    echo '<meta name="viewport" content="width=device-width,initial-scale=1">';
    echo '<link rel="stylesheet" href="/nds/open-hotspot-fas.css">';
    echo '<title>Open-HotSpot</title><body><main class="oh-fas">';
    echo '<section class="oh-card"><p class="oh-brand">Open-HotSpot</p>';
    echo '<h1>تعذر إكمال تسجيل الدخول</h1><p role="alert">', html($message), '</p>';
    echo '<a class="oh-button" href="http://status.client">فتح بوابة الدخول</a>';
    echo '</section></main></body></html>';
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
    foreach (['hid', 'clientmac', 'gatewayaddress', 'authdir'] as $required) {
        if (!isset($values[$required]) || $values[$required] === '') {
            fail_page('بيانات FAS الناقصة.');
        }
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

function period_bounds(string $type, DateTimeImmutable $now): array
{
    $utc = $now->setTimezone(new DateTimeZone('UTC'));
    switch ($type) {
        case 'hourly':
            $start = $utc->setTime((int) $utc->format('H'), 0, 0);
            $end = $start->modify('+1 hour');
            break;
        case 'daily':
            $start = $utc->setTime(0, 0, 0);
            $end = $start->modify('+1 day');
            break;
        case 'monthly':
            $start = $utc->modify('first day of this month')->setTime(0, 0, 0);
            $end = $start->modify('+1 month');
            break;
        case 'yearly':
            $start = $utc->setDate((int) $utc->format('Y'), 1, 1)->setTime(0, 0, 0);
            $end = $start->modify('+1 year');
            break;
        case 'none':
            return ['1970-01-01T00:00:00Z', '9999-12-31T23:59:59Z'];
        default:
            fail_page('نوع الفترة غير صالح.');
    }
    return [$start->format('Y-m-d\TH:i:s\Z'), $end->format('Y-m-d\TH:i:s\Z')];
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

$encoded = is_string($_GET['fas'] ?? null) ? $_GET['fas'] : post_value('fas');
$fas = decode_fas_payload($encoded);
$mac = normalized_mac($fas['clientmac']);
$authDir = trim(rawurldecode($fas['authdir']), '/');
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
    if (preg_match('/^[A-Za-z0-9_.-]{1,64}$/', $username) !== 1
        || preg_match('/^[0-9]{4,32}$/', $pin) !== 1) {
        $message = 'اسم المستخدم أو PIN غير صالح.';
    } else {
        try {
            $stmt = $pdo->prepare(
                'SELECT a.id, a.pin_hash, a.pin_salt, a.pin_iter, a.status, a.expires_at,
                        a.profile_id, p.period_type, p.time_limit_s, p.upload_limit_b,
                        p.download_limit_b, p.upload_rate_kbps, p.download_rate_kbps,
                        p.max_devices
                   FROM accounts a JOIN profiles p ON p.id = a.profile_id
                  WHERE a.username = :username AND a.deleted_at IS NULL LIMIT 1'
            );
            $stmt->execute([':username' => $username]);
            $account = $stmt->fetch(PDO::FETCH_ASSOC);
            $now = new DateTimeImmutable('now', new DateTimeZone('UTC'));
            $expired = $account && $account['expires_at'] !== null
                && new DateTimeImmutable($account['expires_at'], new DateTimeZone('UTC')) <= $now;
            if (!$account || $account['status'] !== 'active' || $expired
                || !open_hotspot_verify_pin(
                    $pin,
                    (string) $account['pin_hash'],
                    (string) $account['pin_salt'],
                    (int) $account['pin_iter']
                )) {
                $message = 'بيانات الدخول غير صحيحة.';
            } else {
                [$periodStart, $periodEnd] = period_bounds((string) $account['period_type'], $now);
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
                                 :policy_snapshot, datetime("now", "+2 minutes"), "pending")'
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
echo '<!doctype html><html lang="ar" dir="rtl"><meta charset="UTF-8">';
echo '<meta name="viewport" content="width=device-width,initial-scale=1">';
echo '<link rel="stylesheet" href="/nds/open-hotspot-fas.css">';
echo '<title>Open-HotSpot</title><body><main class="oh-fas"><section class="oh-card">';
echo '<p class="oh-brand">Open-HotSpot</p><h1>تسجيل الدخول إلى الشبكة</h1>';
if ($message !== '') {
    echo '<p role="alert">', html($message), '</p>';
}

if ($authKey !== '') {
    $token = hash('sha256', $fas['hid'] . fas_key());
    $authAction = 'http://' . $gateway . '/' . $authDir . '/';
    echo '<form method="get" action="', html($authAction), '">';
    echo '<input type="hidden" name="tok" value="', html($token), '">';
    echo '<input type="hidden" name="custom" value="', html($authKey), '">';
    echo '<input type="hidden" name="redir" value="', html($origin), '">';
    echo '<button type="submit">متابعة</button></form>';
} else {
    echo '<form class="oh-login-form" method="post" action="', html($postAction), '">';
    echo '<label>اسم المستخدم <input name="username" required maxlength="64" autocomplete="username"></label>';
    echo '<label>PIN <input name="pin" required inputmode="numeric" type="password" maxlength="32" autocomplete="current-password"></label>';
    echo '<input type="hidden" name="fas" value="', html($encoded), '">';
    echo '<button class="oh-button" type="submit">دخول</button></form>';
}
echo '</section></main></body></html>';
