# فِلمنَا — تطبيق iOS (IPA بلا App Store)

تطبيق واحد يفتح الموقع داخل `WKWebView` حقيقي، يلتقط رابط البث من داخل مشغّل خارجي،
ينزّل الفيديو إلى الجهاز، ويشغّله بلا إنترنت.

## الملفات

```
projects/flix-ios/
├── project.yml                          وصف مشروع XcodeGen (بلا .pbxproj ثنائي)
├── build-ipa.ps1                        بناء IPA على GitHub Actions وتنزيله لسطح المكتب
├── .github/workflows/ipa.yml             آلية macOS تبني الملف غير الموقّع
└── Flix/Sources/
    ├── Info.plist                       flixapp:// + ATS للوسائط
    ├── FlixApp.swift                    نقطة الدخول
    ├── RootView.swift                   تابات + شريط «رابط بث جاهز للتنزيل»
    ├── WebShellView.swift               WKWebView + sniffer في كل إطار + استقبال flixapp://
    ├── MediaSniffer.swift               تجميع روابط m3u8/mp4 المكتشفة
    ├── DownloadManager.swift            mp4 عبر URLSession، m3u8 عبر AVAssetDownloadTask
    ├── LibraryView.swift                المكتبة + مشغّل من الملف المحلي
    ├── DownloadsView.swift              حالة كل تنزيل وتقدّمه
    └── MediaStore.swift                 فهرس المكتبة داخل Documents
```

## الطريق الأقصر إلى ملف IPA

```powershell
# مرة واحدة فقط: سجّل دخول GitHub
gh auth login

# ثم:
pwsh -NoProfile -File "C:\Users\Administrator\Downloads\222222\projects\flix-ios\build-ipa.ps1"
```

السكربت ينشئ مستودعاً خاصاً، يدفع المشروع، يشغّل `ipa.yml` على آلية macOS مجانية،
ينتظر البناء (~5 دقائق)، وينزل الناتج إلى `Desktop\Flix-unsigned.ipa` مع SHA-256.

بديل: انقر مرتين على `Desktop\فلما - بناء IPA.bat` — نفس الشيء بغلاف.

## التوقيع بشهادة مجانية 7 أيام

1. نزّل **Sideloadly** (ويندوز) أو **AltStore**.
2. اسحب `Flix-unsigned.ipa` إلى النافذة، اختر جهازك، سجّل الدخول بـ Apple ID عادي.
3. Start → يوقّع بشهادة تطوير مجانية صالحة **7 أيام** ويثبّت التطبيق.
4. على الآيفون: Settings › General › VPN & Device Management › ائتمن المطوّر.
5. بعد 7 أيام: أعد التوقيع بنفس الطريقة (Refresh في AltStore). التنزيلات تبقى
   إن ثبّتت فوق النسخة القديمة بنفس `app.filmna.flix`.

| قيد الحساب المجاني | القيمة |
|---|---|
| صلاحية الشهادة | 7 أيام |
| تطبيقات موقّعة في وقت واحد | 3 |
| أجهزة لكل Apple ID | جهاز واحد |
| Push / App Groups / iCloud | غير متاحة |

## كيف يصل الفيديو إلى التنزيل

1. `WebShellView` يحقن سكربتاً بـ`forMainFrameOnly: false` — أي داخل iframe المشغّل
   الخارجي أيضاً. هذا الشيء الوحيد الذي لا تستطيع صفحة الويب منعه.
2. السكربت يراقب `<video>` و`fetch` و`XMLHttpRequest`، ويرسل أي رابط `m3u8`/`mp4`
   إلى التطبيق عبر `messageHandlers.flix`.
3. `MediaSniffer` يجمعها (بلا تكرار لكل مضيف)، ويظهر شريط فوق الصفحة:
   زر واحد لكل رابط → `DownloadManager.enqueue`.
4. `mp4` → `URLSession` خلفي؛ `m3u8` → `AVAssetDownloadURLSession` يخزّن حزمة
   قابلة للتشغيل بلا شبكة.
5. المكتبة تشغّل من مسار داخل `Documents` فقط: `AVPlayer` بلا شبكة ولا DRM.

بديل يدوي: زر «تنزيل رابط» يلصق فيه رابطاً مباشراً، أو `flixapp://download?url=…&title=…`.

## حالة التحقق

| ما تم | كيف |
|---|---|
| بناء الموقع الحي وكل مساراته | Playwright + curl على `flix.5tcj5876g9.workers.dev` |
| تشغيل vidlink وflicky وvidrock داخل الصفحة | readyState 4، مدة 1:50:58 |
| كود Swift | **لم يُبنَ هنا** — لا macOS/Xcode على ويندوز |
| بناء IPA | **لم يُشغَّل** — يحتاج `gh auth login` منك ثم يعمل السكربت |

قيود حقيقية في التطبيق نفسه:

- **لا يسحب الفيديو من مشغّل يستخدم WebSocket مشفّراً أو DRM** — Widevine/PlayReady
  لا يُنزَّل بلا ترخيص، وهذا قيد المنصة لا قيد الكود.
- **لا يخزّن مكتبة أفلام كاملة** — التنزيل عمل واحد بضغطة، والمساحة على الجهاز.
- **IPA غير موقّع لا يفتح على iPhone.** التوقيع خطوة على جهازك بحسابك.
