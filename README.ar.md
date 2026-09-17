# Open-HotSpot — التوثيق العربي

طبقة إدارة LuCI محلية لـ **openNDS** على OpenWrt. توفر إدارة الحسابات، ملفات
السرعة والحصة، القسائم، والأجهزة المرتبطة بالحساب، مع قاعدة SQLite محلية.

## الحالة الحالية

- الراوتر الاختباري: Linksys EA8300، إصدار OpenWrt 25.12.5.
- عنوان الإدارة: `192.168.70.1`.
- WAN يعمل بعنوان `192.168.50.156/24` والبوابة وDNS هما `192.168.50.1`.
- الحزمة المثبتة: `luci-app-open-hotspot 1.2.0-r16`.
- openNDS يعمل، وFAS المحلي يعمل على المنفذ `2080` والمسار `/nds/fas.php`.
- `dnsmasq-full` مثبت مع دعم `nftset`.

الحزمة المختبرة موجودة في
[`dist/luci-app-open-hotspot-1.2.0-r16.apk`](dist/luci-app-open-hotspot-1.2.0-r16.apk)،
وبصمة SHA-256 هي:
`cfc03526e5e8c9cfe6dace0968b24ff4e63aabeab72144232196ed0ded7ad16a`.

يتحقق الإصدار r16 من حمولة FAS الموثقة التي تستخدم الحقل `hid`، ويقبل أيضاً
التسمية التوافقية `client_hid` التي ظهرت في بعض مسارات العميل captive portal.
أما الطلبات التي لا تحمل سياق FAS موثقاً فتبقى مرفوضة لأسباب أمنية.

## عقد عناوين بوابة الدخول

صفحة حالة عميل openNDS المدمجة متاحة على العنوان
`http://status.client`، وقد ضُبط هذا الاسم ليشير إلى عنوان LAN للراوتر
(`192.168.70.1`). أما صفحة تسجيل الدخول العربية/الإنجليزية التي أُنشئت في
المشروع فتخدمها نقطة FAS المحلية `/nds/fas.php`، لكن يجب الوصول إليها عبر
تدفق بوابة openNDS حتى تصلها بيانات سياق FAS الموثقة.

لذلك فإن فتح `/nds/fas.php` مباشرةً، أو فتحه من فحص captive portal لا يرسل
حمولة FAS، يعرض عمداً صفحة الخطأ المنسقة «بيانات FAS الناقصة» ولا يقوم
بمصادقة العميل. استخدم زر **فتح بوابة الدخول** في الصفحة، أو افتح
`http://status.client` عبر HTTP العادي، ثم أرسل نموذج الدخول.

الصورة التي تعرض بطاقة «بيانات FAS الناقصة» هي صفحة تشخيص آمنة ومغلقة
افتراضياً، وليست دليلاً على غياب صفحة FAS من حزمة APK؛ فالصفحة وملف CSS
مضمّنان في الإصدار r16. وما يزال اختبار العميل الفعلي المتبقي هو إتمام
التسلسل: البوابة → تسجيل FAS → ظهور العميل بحالة `Authenticated` في openNDS.

## التوزيع عبر GitHub

صفحة **Packages** تبقى فارغة بشكل صحيح؛ GitHub Packages لا يدعم صيغة APK
الخاصة بـ OpenWrt ضمن سجلاته المدعومة. الحزمة موجودة داخل المستودع، وأضفت
Workflow ينشرها تلقائياً كملف مرفق في **Releases** عند دفع وسم يبدأ بـ `v`.
راجع [صفحة الإصدارات](https://github.com/opentik-dev/open-hotspot/releases).

تم حفظ نسخة احتياطية قبل التغيير، كما تم أرشفة حالة التطبيق القديم. لم يُنفذ
مسح مصنع حرفي حتى تبقى استعادة الاتصال عبر LAN وSSH ممكنة.

## التثبيت

```sh
tar -C .build -cf - luci-app-open-hotspot-1.2.0-r16.apk | \
  ssh root@192.168.70.1 'tar -xf - -C /tmp'
ssh root@192.168.70.1 'apk add --allow-untrusted /tmp/luci-app-open-hotspot-1.2.0-r16.apk'
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

للتجربة الحالية اتصل بالشبكة المفتوحة `Open-HotSpot-Test`، ثم أعد فتح صفحة
الدخول إذا كانت مفتوحة قبل تثبيت r16، وسجّل بالحساب التجريبي الذي أُنشئ على
الراوتر. لا تُعدّ التجربة مكتملة حتى يظهر العميل `Authenticated` في
`ndsctl status`.

طريقة بناء SDK/feeds موثقة مع روابط OpenWrt الرسمية في النسخة الإنجليزية من
هذا الملف.
