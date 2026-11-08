# الميزان برو — تطبيق أندرويد (Flutter)

نقطة بيع + مخزون + دفتر كريدي + محاسبة ومصاريف لمحلات المواد الغذائية.
يعمل **بدون إنترنت**، والبيانات محفوظة في قاعدة SQLite داخل الهاتف.

## الطريقة 1: بناء APK تلقائياً عبر GitHub (دون تثبيت أي شيء)
1. أنشئ حساباً على github.com ثم مستودعاً جديداً (Repository).
2. ارفع كل محتويات هذا المجلد إلى المستودع (بما فيها المجلد المخفي `.github`).
3. افتح تبويب **Actions** ← **Build APK** ← ينتظر 5–8 دقائق.
4. من صفحة التشغيل نزّل الملف **mizan-pro-apk** (يحتوي `app-release.apk`) وثبّته على الهاتف.

## الطريقة 2: البناء على حاسوبك
1. ثبّت Flutter (flutter.dev) وAndroid Studio.
2. داخل هذا المجلد:
   ```
   flutter create --platforms=android --org dz.mizanpro --project-name mizan_pro .
   flutter pub get
   flutter build apk --release
   ```
3. الملف يظهر في `build/app/outputs/flutter-apk/app-release.apk`.

## للنشر على Google Play
الـ APK الناتج موقّع بمفتاح تجريبي (يصلح للتثبيت المباشر). للنشر على المتجر أنشئ مفتاحاً خاصاً (keystore)
واتبع: https://docs.flutter.dev/deployment/android — ويفضّل رفع `flutter build appbundle`.

## ملاحظات
- البيانات الأولى (12 سلعة) أمثلة فقط؛ عدّلها أو احذفها من شاشة المخزون.
- لا يوجد نسخ احتياطي سحابي بعد: حذف التطبيق يحذف بياناته.
