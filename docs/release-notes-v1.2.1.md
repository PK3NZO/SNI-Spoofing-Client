# SNI-Spoofing Client v1.2.1

## English

### Highlights

- Native macOS release track for both `arm64` and `x86_64`
- Separate DMG assets for Apple Silicon and Intel Macs
- Cleaner release packaging flow with dedicated build, sign, DMG, notarize, and checksum scripts
- Improved public-repo hygiene checks to reduce the risk of leaking private local paths or signing metadata
- Refreshed GitHub-facing project docs, issue templates, contribution guide, and security policy

### Assets

- `SniSpoofingClient-macos-arm64-v1.2.1.dmg`
- `SniSpoofingClient-macos-x86_64-v1.2.1.dmg`
- `checksums-v1.2.1.txt`

### Notes

- Download the DMG matching your Mac architecture
- `Proxy` and `Tunnel` modes should both be validated before broad rollout
- If you hit a packaging or connection bug, include architecture and mode in the issue report

## فارسی

### نکات اصلی

- ریلیز native برای macOS روی هر دو معماری `arm64` و `x86_64`
- دو فایل DMG جدا برای Apple Silicon و Intel
- جریان ریلیز تمیزتر با اسکریپت‌های مجزا برای build، sign، DMG، notarize و checksum
- اضافه شدن check های hygiene برای کم کردن ریسک نشت path شخصی یا metadata مربوط به signing
- بازنویسی بخش GitHub-facing شامل README، template های issue، راهنمای contribution و policy امنیت

### فایل‌های ریلیز

- `SniSpoofingClient-macos-arm64-v1.2.1.dmg`
- `SniSpoofingClient-macos-x86_64-v1.2.1.dmg`
- `checksums-v1.2.1.txt`

### یادداشت

- DMG متناسب با معماری سیستم خود را دانلود کنید
- بهتر است قبل از rollout گسترده، هر دو حالت `Proxy` و `Tunnel` تست شوند
- اگر bug مربوط به پکیجینگ یا اتصال دیدید، معماری و mode را داخل issue ذکر کنید
