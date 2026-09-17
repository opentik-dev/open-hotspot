# Open-HotSpot — التوثيق العربي

طبقة إدارة LuCI محلية لـ **openNDS** على OpenWrt. توفر إدارة الحسابات، ملفات
السرعة والحصة، القسائم، والأجهزة المرتبطة بالحساب، مع قاعدة SQLite محلية.

## الحالة الحالية

- الراوتر الاختباري: Linksys EA8300، إصدار OpenWrt 25.12.5.
- عنوان الإدارة: `192.168.70.1`.
- WAN يعمل بعنوان `192.168.50.156/24` والبوابة وDNS هما `192.168.50.1`.
- الحزمة المثبتة: `luci-app-open-hotspot 1.2.0-r14`.
- openNDS يعمل، وFAS المحلي يعمل على المنفذ `2080` والمسار `/nds/fas.php`.
- `dnsmasq-full` مثبت مع دعم `nftset`.

الحزمة المختبرة موجودة في
[`dist/luci-app-open-hotspot-1.2.0-r14.apk`](dist/luci-app-open-hotspot-1.2.0-r14.apk)،
وبصمة SHA-256 هي:
`a2b2cb0021bcdd7238b4b6c29351731d6f897b7063bfcdb3f4314eba86970ca8`.

## التوزيع عبر GitHub

صفحة **Packages** تبقى فارغة بشكل صحيح؛ GitHub Packages لا يدعم صيغة APK
الخاصة بـ OpenWrt ضمن سجلاته المدعومة. الحزمة موجودة داخل المستودع، وأضفت
Workflow ينشرها تلقائياً كملف مرفق في **Releases** عند دفع وسم يبدأ بـ `v`.
راجع [صفحة الإصدارات](https://github.com/opentik-dev/open-hotspot/releases).

تم حفظ نسخة احتياطية قبل التغيير، كما تم أرشفة حالة التطبيق القديم. لم يُنفذ
مسح مصنع حرفي حتى تبقى استعادة الاتصال عبر LAN وSSH ممكنة.

## التثبيت

```sh
tar -C .build -cf - luci-app-open-hotspot-1.2.0-r14.apk | \
  ssh root@192.168.70.1 'tar -xf - -C /tmp'
ssh root@192.168.70.1 'apk add --allow-untrusted /tmp/luci-app-open-hotspot-1.2.0-r14.apk'
```

بعدها افتح: **Services → Open-HotSpot → Setup**. التفعيل المحلي الصريح:

```sh
ssh root@192.168.70.1 '/usr/lib/open-hotspot/activate-local-fas.sh enable'
```

للتراجع:

```sh
ssh root@192.168.70.1 '/usr/lib/open-hotspot/activate-local-fas.sh rollback'
```

## لقطات من LuCI

التحذير الأصفر في اللقطات مقصود؛ يجب تعيين كلمة مرور root قبل التسليم.

![الإعداد](docs/screenshots/setup.jpg)

![الملفات](docs/screenshots/profiles.jpg)

![الحسابات](docs/screenshots/accounts.jpg)

![الأجهزة](docs/screenshots/devices.jpg)

![القسائم](docs/screenshots/vouchers.jpg)

## ما تبقى قبل التسليم

يلزم اختبار عميل Wi‑Fi/LAN منفصل يمر فعلياً بتسلسل captive portal → FAS →
BinAuth → جلسة openNDS، ثم اختبار الحصص وتعدد الأجهزة والقسائم. كما يجب تعيين
كلمة مرور root. تفاصيل الاختبارات ونسخ الاستعادة وSHA-256 موجودة في
[`specs/001-open-hotspot/quickstart.md`](specs/001-open-hotspot/quickstart.md).

طريقة بناء SDK/feeds موثقة مع روابط OpenWrt الرسمية في النسخة الإنجليزية من
هذا الملف.
