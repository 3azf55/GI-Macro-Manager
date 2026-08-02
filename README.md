# Macro Manager v1.5.2

مدير ماكرو عام مبني على **AutoHotkey v1** مع واجهة **C# WinForms + WebView2**.  
يقرأ الشخصيات والماكروهات ديناميكيًا من `Macros/registry.ini` ويشغّل كل ماكرو في عملية AutoHotkey فرعية مستقلة.

## المزايا

- واجهة WebView2 بوضعين داكن وفاتح.
- اختيار الشخصيات والماكروهات ديناميكيًا دون أسماء ثابتة داخل المحرك.
- استيراد ملفات AutoHotkey v1 وتشغيلها تحت تحكم Trigger الخاص بمدير الماكرو.
- اكتشاف أول Hotkey داخل السكربت المستورد تلقائيًا.
- دعم `RunMacro()` أو قسم Auto-execute عند عدم وجود Hotkey.
- طبقة توافق لفحوص `GetKeyState(..., "P")` الخاصة بالـTrigger الأصلي.
- إضافة الماكروهات وحذفها وتصديرها.
- إعادة ترتيب ماكروهات الشخصية بالضغط المطول والسحب.
- حفظ الترتيب داخل `Macros/registry.ini`.
- تشغيل اللعبة من Dashboard مع طلب ملف EXE عند عدم تحديد المسار.
- وضع Skip Dialogs واختصارات قابلة للتخصيص.
- رابط مجتمع Discord مضمّن في الواجهة.

## المتطلبات

- Windows 10 أو Windows 11.
- AutoHotkey **v1.1 Unicode**.
- .NET 8 SDK للبناء.
- Microsoft Edge WebView2 Runtime.

> المشروع لا يدعم سكربتات AutoHotkey v2 عبر المحرك الحالي.

## البناء

من جذر المشروع:

```bat
scripts\build-and-stage.cmd
```

أو عبر PowerShell:

```powershell
.\scripts\build-and-stage.ps1
```

ينشئ السكربت مجلدًا نهائيًا باسم:

```text
dist\
```

## التشغيل

بعد البناء شغّل:

```text
dist\UMM.Engine.ahk
```

يبدأ المحرك `UMM.UI.exe` تلقائيًا ويستخدم File Bridge للتواصل مع واجهة WebView2.

## بنية المشروع

```text
.
├── UMM.Engine.ahk
├── UIHost/
│   ├── UMM.UI.csproj
│   ├── MainForm.cs
│   ├── BridgeProtocol.cs
│   ├── Program.cs
│   └── ui/
│       ├── index.html
│       ├── styles.css
│       ├── app.js
│       └── build-info.json
├── Macros/
│   ├── registry.ini
│   ├── Runtime/
│   │   └── MacroRuntime.ahk
│   └── User/
├── Assets/
├── scripts/
└── docs/
```

## الماكروهات المرفقة

جميع الماكروهات المرفقة حزم عادية قابلة للحذف والتصدير داخل:

```text
Macros\User\<Character>\<Macro>\
```

وتحتوي عادةً:

```text
manifest.ini
source.ahk
```

تُعرّف معلومات العرض والترتيب ومسار السكربت داخل:

```text
Macros\registry.ini
```

راجع [تنسيق حزم الماكرو](docs/MACRO_PACKAGES.md).

## استيراد ملفات AHK

يحفظ مدير الماكرو الملف الأصلي باسم `source.ahk` وينشئ ملف تشغيل داخليًا عند الحاجة.

ترتيب التحليل:

1. أول Hotkey عادي في الملف.
2. دالة `RunMacro()`.
3. قسم Auto-execute.

عند اكتشاف Hotkey، يصبح Trigger الخاص بمدير الماكرو مسؤولًا عن بدء العملية وإيقافها.  
الملفات التي تعتمد على Includes أو DLL أو INI أو أصول خارجية تحتاج تلك الملفات بجانب الحزمة.

## الأمان

ملفات AutoHotkey المستوردة تعمل بصلاحيات المستخدم ويمكنها قراءة الملفات أو تشغيل البرامج أو حذف البيانات.  
استورد السكربتات من مصادر موثوقة فقط. اقرأ [سياسة الأمان](SECURITY.md).

## المجتمع

- Discord: https://discord.gg/H8HNhvqqm
- GitHub: أضف رابط المستودع داخل `UIHost/ui/app.js` بعد إنشاء المستودع.

## النشر

لا ترفع مجلد `dist` إلى سجل Git.  
ابنِ المشروع، اضغط مجلد `dist` كملف ZIP، ثم ارفعه كملف مرفق داخل **GitHub Releases**.

## الرخصة

لم تُحدد رخصة للمشروع بعد. قبل نشره كمشروع مفتوح المصدر، اختر رخصة مناسبة وأضف ملف `LICENSE`.
