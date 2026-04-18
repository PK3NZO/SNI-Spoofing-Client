# SNI-Spoofing Client

Native desktop client for running SNI-based DPI bypass workflows on macOS, with support for both `Proxy` and `Tunnel` modes.

[![Version](https://img.shields.io/badge/version-1.2.1-2563eb.svg)](https://github.com/PK3NZO/SNI-Spoofing-Client/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-111827.svg)](https://github.com/PK3NZO/SNI-Spoofing-Client/releases)
[![License](https://img.shields.io/badge/license-GPL--3.0-16a34a.svg)](LICENSE)

## English

### Overview

SNI-Spoofing Client is a native macOS application built for advanced censorship-circumvention workflows that rely on SNI spoofing, local proxying, and packet-tunnel based routing.

Current public release target:

- macOS app
- Apple Silicon (`arm64`) build
- Intel (`x86_64`) build
- `VLESS`, `VMess`, `Trojan`, and `Shadowsocks` config parsing
- `Proxy` mode and `Tunnel` mode

### Downloads

Download the latest signed release assets from:

- [GitHub Releases](https://github.com/PK3NZO/SNI-Spoofing-Client/releases)

Expected macOS assets for `v1.2.1`:

- `SniSpoofingClient-macos-arm64-v1.2.1.dmg`
- `SniSpoofingClient-macos-x86_64-v1.2.1.dmg`
- `checksums-v1.2.1.txt`

### Features

- Native SwiftUI macOS app
- Clean bilingual UI: English + Persian
- Two connection modes:
  - `Proxy`
  - `Tunnel`
- Embedded Xray runtime per architecture
- Live connection workflow visibility
- Download / upload / total usage cards
- Validation hints for required inputs
- Config parsing for multiple protocols

### macOS Requirements

- macOS 14 or newer
- Administrator access for privileged networking actions
- Apple Silicon Mac for `arm64` release
- Intel Mac for `x86_64` release

### Installation

For end users:

1. Download the correct DMG for your Mac architecture.
2. Open the DMG.
3. Drag the app into `Applications`.
4. Launch the app.
5. Grant any required macOS permissions when prompted.

### Screenshots

Screenshots will be added here before/after release polish.

<!--
Later insert screenshots like this:

![Main Window](docs/screenshots/main-window.png)
![Connection Flow](docs/screenshots/connection-flow.png)
-->

### Build From Source

```bash
cd macos-arm
./generate_xcode_project.sh
./build_arm_debug.sh
./build_x86_64_debug.sh
```

Release build helpers:

```bash
cd macos-arm
./build_arm_release.sh
./build_x86_64_release.sh
./package_arm_release.sh
./package_x86_64_release.sh
./generate_checksums.sh
```

Detailed macOS signing, DMG, and notarization guidance:

- [macOS Release Guide](docs/macos-release-guide.md)

### Reporting Issues

If you hit a bug:

- open a GitHub issue with logs, screenshots, and reproduction steps
- include whether you used `Proxy` or `Tunnel`
- include whether your Mac is `arm64` or `x86_64`

### Credits

- Original project direction and release ownership: `PK3NZO`
- Special shoutout: [patterniha/SNI-Spoofing](https://github.com/patterniha/SNI-Spoofing)

---

## فارسی

### معرفی

SNI-Spoofing Client یک اپلیکیشن native برای macOS است که برای سناریوهای دور زدن DPI با تکیه بر SNI spoofing، لوکال پروکسی، و packet tunnel ساخته شده است.

هدف ریلیز عمومی فعلی:

- اپلیکیشن macOS
- نسخه جدا برای `arm64`
- نسخه جدا برای `x86_64`
- پشتیبانی از لینک‌های `VLESS`، `VMess`، `Trojan` و `Shadowsocks`
- دو حالت اتصال:
  - `Proxy`
  - `Tunnel`

### دانلود

جدیدترین نسخه‌ها از اینجا قابل دریافت هستند:

- [GitHub Releases](https://github.com/PK3NZO/SNI-Spoofing-Client/releases)

نام فایل‌های مورد انتظار برای `v1.2.1`:

- `SniSpoofingClient-macos-arm64-v1.2.1.dmg`
- `SniSpoofingClient-macos-x86_64-v1.2.1.dmg`
- `checksums-v1.2.1.txt`

### قابلیت‌ها

- اپلیکیشن native با SwiftUI
- رابط کاربری دو زبانه: فارسی و انگلیسی
- دو حالت اتصال:
  - `Proxy`
  - `Tunnel`
- Xray داخلی متناسب با معماری سیستم
- نمایش مرحله‌ای workflow اتصال
- نمایش زنده مصرف دانلود، آپلود و مجموع مصرف
- هایلایت ورودی‌های ناقص در زمان validation
- پشتیبانی از چند پروتکل مختلف

### نیازمندی‌ها

- macOS 14 به بالا
- دسترسی Administrator برای بعضی عملیات شبکه
- مک Apple Silicon برای نسخه `arm64`
- مک Intel برای نسخه `x86_64`

### نصب

برای کاربران نهایی:

1. فایل DMG مناسب معماری سیستم خود را دانلود کنید.
2. DMG را باز کنید.
3. اپ را به پوشه `Applications` بکشید.
4. برنامه را اجرا کنید.
5. اگر macOS مجوز خواست، آن‌ها را تأیید کنید.

### اسکرین‌شات‌ها

اسکرین‌شات‌ها بعد از پولیش نهایی اینجا اضافه می‌شوند.

### بیلد از سورس

```bash
cd macos-arm
./generate_xcode_project.sh
./build_arm_debug.sh
./build_x86_64_debug.sh
```

برای ریلیز:

```bash
cd macos-arm
./build_arm_release.sh
./build_x86_64_release.sh
./package_arm_release.sh
./package_x86_64_release.sh
./generate_checksums.sh
```

راهنمای کامل ساین، ساخت DMG و notarization:

- [راهنمای انتشار macOS](docs/macos-release-guide.md)

### گزارش باگ

اگر به مشکل خوردید:

- داخل GitHub issue باز کنید
- لاگ، اسکرین‌شات و مراحل بازتولید را بفرستید
- مشخص کنید از `Proxy` استفاده کرده‌اید یا `Tunnel`
- مشخص کنید سیستم شما `arm64` است یا `x86_64`

### قدردانی

- انتشار و نگهداری پروژه: `PK3NZO`
- تشکر ویژه از: [patterniha/SNI-Spoofing](https://github.com/patterniha/SNI-Spoofing)
