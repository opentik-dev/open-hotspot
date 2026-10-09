# خطة معالجة تعارض البوابة وخدمات الراوتر

**الحالة:** Proposed — لا تغيير على الراوتر حتى اعتماد نافذة تنفيذ

## نتيجة الدليل الميداني

عملت مشاركة SMB، سنترال SIP، مسار Tailscale، وأجهزة IoT عندما أوقفت
openNDS وOpen-HotSpot وFAS. كان إعداد openNDS على واجهة الخدمة المشتركة
يسمح فقط بمنفذ FAS في `users_to_router` ثم يرفض بقية الاتصالات إلى الراوتر.
هذه ليست مشكلة في KSMBD أو Asterisk أو Tailscale.

openNDS 11 يدعم UCI وnftables وقواعد العميل المفصلة، لكن
`users_to_router` هو حد وصول إلى **الراوتر نفسه** وليس سياسة "بعد تسجيل
الدخول فقط". لا يحول `custombinauth` أو قائمة `authenticated_users` هذه
القواعد إلى حماية جلسة لخدمات المستضافة على عنوان الراوتر.

مصادر القرار: [ADR-007](decisions/ADR-007-separate-captive-management-service-planes.md)،
[سجل فجوة INT-023](integration-gap-register.md)، وسجل التشغيل OP-115/116.

## التصميم المستهدف

لا تُغيّر الخطة العناوين أو أسماء SSID أو VLAN من تلقاء نفسها. يختارها
المشغل في نافذة التنفيذ بعد جردها.

```text
                    WAN / Internet
                           |
     +---------------------+----------------------+
     |                     |                      |
br-lan                br-guest                br-hotspot
خدمات وإدارة          Transit/onboarding      Captive portal
NAS / PBX /            منفذ/شبكة لراوتر        SSID أو VLAN مستقل
كاميرات / Tailscale    تابع أو جهاز عابر        openNDS + FAS فقط
     |                     |                      |
     +-- لا openNDS         +-- WAN فقط            +-- إنترنت بعد المصادقة

br-iot
SSID/VLAN مستقل لأجهزة IoT -> WAN فقط، بلا بوابة ولا وصول إلى br-lan.
```

### لماذا `br-hotspot` وليس اسم صفحة مختلف؟

الاسم أو FQDN لا يفصلان nftables أو DHCP أو جدار الحماية. في openNDS 11
يجب أن تكون `gatewayinterface` جهاز bridge وليس واجهة Wi-Fi مباشرة. لذلك
تنشأ شبكة UCI مستقلة وجهاز bridge مستقل (`br-hotspot`) حتى إن استُخدم SSID
إضافي فقط من دون منفذ سلكي أو VLAN في المرحلة الأولى.

### الأدوار الثابتة

| المستوى | الدور | سياسة الوصول |
|---|---|---|
| `br-lan` | إدارة وخدمات محلية | لا openNDS؛ NAS/PBX/كاميرات/LuCI/SSH وفق سياسة LAN الحالية. |
| `br-guest` | Transit لراوتر تابع أو جهاز يريد WAN بلا تعارض عنوان | DHCP/DNS محليان وWAN فقط؛ لا forwarding إلى `br-lan`. لا تشدّدها قبل إثبات مسار إدارة بديل. |
| `br-hotspot` | مستخدمو البوابة | openNDS وFAS فقط؛ إنترنت بعد المصادقة؛ لا NAS/PBX/LuCI/SSH/Tailscale افتراضيًا. |
| `br-iot` | لمبات/أفياش وأجهزة لا تعرض بوابة | WAN فقط، وDNS/DHCP/NTP اللازم؛ لا trusted-MAC أو bypass غير موثق. |
| `tailscale0` | إدارة خارجية | وصول دقيق إلى `br-lan` والخدمات المعتمدة؛ منع الوصول الافتراضي إلى captive وIoT. |

## المساران المدعومان

### A. المسار الإنتاجي — الفصل الكامل

1. أبقِ `br-lan` للخدمات والإدارة وأبقِ `br-guest` Transit كما هو.
2. أنشئ `br-hotspot` مع DHCP ونطاق غير متداخل وSSID ضيف جديد.
3. انقل `opennds.@opennds[0].gatewayinterface` إلى جهاز `br-hotspot` فقط.
4. فعّل FAS الحالي (`status.client` وport 2080) على هذا المسار فقط.
5. أنشئ `br-iot` منفصلًا بسياسة WAN-only، وألحق به SSID/أجهزة IoT.
6. ضع قواعد Tailscale صريحة لخدمات `br-lan` ولا تعلن subnet route للـ captive
   أو IoT من دون قرار مستقل.

هذا هو المسار الوحيد الذي يضمن في آن واحد بوابة حقيقية، وخدمات محلية سليمة،
وعزلًا لا يفتح NAS أو PBX لعميل غير مصادق.

### B. مسار مؤقت متوافق مع `br-lan` المشتركة — غير إنتاجي

يبقى openNDS على `br-lan` وتضاف سماحات `users_to_router` التالية فقط بعد
نسخة احتياطية واختبار عميل disposable:

| الخدمة | السماح المطلوب | لا يُفتح |
|---|---|---|
| FAS | TCP/2080 | أي منفذ إدارة إضافي |
| SMB الحديث | TCP/445 | NetBIOS 137–139 ما لم يثبت احتياج فعلي |
| SIP | UDP/5060 | منافذ SIP بديلة غير مستخدمة |
| RTP | UDP/10000–20000 (نطاق Asterisk المضبوط حاليًا) | UDP عام أو منافذ أخرى |

هذه القواعد تحل وصول CX Files وWave Lite، لكنها قد تكون متاحة قبل تسجيل
الدخول لأن مسارها `users_to_router`. لهذا لا تُستخدم لإتاحة Tailscale أو
LuCI أو SSH، ولا تعد بديلاً عن فصل الشبكات. صلاحيتها محدودة بزمن ومرفقة
بخطة إزالة عند إكمال المسار A.

إذا كانت حاجة العمل هي أن مستخدم البوابة يصل إلى NAS/PBX **بعد** المصادقة
فقط، فلا تستضف الخدمة على عنوان الراوتر نفسه: انقلها إلى مضيف خدمة/شبكة
خلف الراوتر، ثم استخدم قواعد `authenticated_users` وfirewall forwarding
المحددة نحو ذلك المضيف. هذا يستفيد من ترتيب قواعد authenticated في openNDS
11 من دون كشف خدمة الراوتر قبل المصادقة.

## الاستفادة الصحيحة من openNDS 11

- المحافظة على `custombinauth` وFAS المحلي الحالي؛ لا نستبدل BinAuth أو
  نستخدم أوامر `ndsctl` منه.
- استخدام UCI وnftables المدعومين، لا قواعد `nft` يدوية تختفي عند restart.
- الاستفادة من تحليل قواعد البروتوكول/المنفذ وfrom/to في v11 فقط لسياسات
  موثقة ومختبرة؛ لا تعتمد هذه الميزة لتجاوز حد router-service.
- إبقاء `users_to_router_passthrough=0`؛ تفعيله ينقل مسؤولية الخدمات
  الأساسية إلى firewall وقد يعطل الراوتر.
- عدم استعمال trusted/preemptive MAC كحل لأجهزة IoT؛ IoT يحصل على شبكة
  WAN-only مستقلة.

سجل تغييرات v11 يذكر UCI/nftables وتحسينات `custombinauth` وقواعد العميل،
لكنه لا يضيف ربطًا تلقائيًا بين `users_to_router` وحالة المصادقة. لذلك لا
يوجد مفتاح v11 آمن يزيل هذا التعارض على `br-lan` المشتركة.

## حواجز تمنع التكرار في المشروع

قبل إعادة تفعيل البوابة، يضاف إلى الحزمة:

1. **Service-plane guard:** يفشل activation/preflight إذا كانت واجهة openNDS
   هي جهاز `br-lan` الذي يستضيف KSMBD أو Asterisk أو Tailscale، إلا عند
   اختيار profile مؤقت صريح ومؤرخ.
2. **Service-policy manifest:** قائمة ثابتة ومتحقق منها للخدمات المؤقتة
   (FAS/SMB/SIP/RTP)؛ لا يقبل UI نص nft أو منافذ حرة.
3. **Rollback checkpoint:** تصدير إعدادات network/wireless/firewall/opennds
   وUCI للخدمات قبل كل تغيير، مع استبعاد الأسرار من Git والسجل.
4. **Runtime audit:** يطابق gatewayinterface، bridge، zones، FAS listener،
   `users_to_router`، وحالة Tailscale مع التصميم المختار ويصدر FAIL عند
   التضارب.
5. **عقود اختبار:** اختبار يمنع إعادة openNDS إلى جهاز service-plane؛ واختبار
   لرفض subnet متداخل أو forwarding من Transit/IoT إلى `br-lan`.
6. **بوابة قبول ميدانية:** لا يُدمج أو يُنشر تغيير شبكة إلا بعد إثبات منفصل
   لـ portal، NAS، SIP call/RTP، IoT egress، Tailscale، وrollback.

## ترتيب التنفيذ والرجوع

| المرحلة | الإجراء | معيار القبول | الرجوع |
|---|---|---|---|
| 0 | تثبيت الوضع الحالي | الخدمات تعمل والبوابة Paused | لا تغيير |
| 1 | جرد SSID/VLAN/DHCP/zones/routes والخدمات | ملف evidence بلا أسرار | لا تغيير |
| 2 | بناء guard والعقود محليًا | اختبارات repository تمر | revert commit |
| 3 | إنشاء `br-hotspot` وSSID فقط | إدارة `br-lan` وTailscale لا تنقطع | حذف SSID/zone الجديد |
| 4 | ربط openNDS بـ `br-hotspot` | portal/disposable login/Internet تعمل | استعادة openNDS UCI checkpoint |
| 5 | إنشاء `br-iot` | IoT يصل WAN فقط ولا يصل `br-lan` | إزالة zone/forwarding |
| 6 | تقنين `br-guest` | downstream يحصل WAN فقط | استعادة firewall checkpoint |
| 7 | قبول نهائي | كل مصفوفة الاختبار تمر | الرجوع للمرحلة السابقة الناجحة |

## مصفوفة القبول الإلزامية

| المصدر | الوجهة | المتوقع |
|---|---|---|
| Captive قبل المصادقة | `status.client` | متاح |
| Captive قبل المصادقة | Internet/NAS/PBX/Tailscale | محجوب |
| Captive بعد المصادقة | Internet | متاح |
| Management `br-lan` | NAS/PBX/كاميرا | متاح |
| IoT | WAN | متاح |
| IoT | `br-lan`/LuCI/NAS/PBX | محجوب |
| Transit `br-guest` | WAN | متاح |
| Transit `br-guest` | `br-lan` | محجوب |
| Tailnet | الوجهات المعتمدة في `br-lan` | متاح |
| Tailnet | Captive/IoT | محجوب افتراضيًا |

## قيود تشغيلية

- لا تستخدم **Upgrade all**: توجد تحديثات كثيرة تشمل مكونات حساسة مثل kernel
  وLuCI. الترقية تكون على حزمة/نسخة مدروسة في نافذة مستقلة مع rollback.
- لا تشغّل openNDS على `br-lan` مرة أخرى قبل اختيار المسار A أو اعتماد
  مسار B المؤقت مع قبول خطره صراحة.
- لا تغيّر `br-guest` بينما هو مسار الإدارة الوحيد؛ أثبت أولًا اتصال إدارة
  بديلًا عبر `br-lan` أو Tailscale.
