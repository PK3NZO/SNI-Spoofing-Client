# Contributing

## English

Thanks for considering a contribution.

Before opening a pull request:

1. Open an issue first for major changes.
2. Keep changes scoped and reviewable.
3. Test the affected mode:
   - `Proxy`
   - `Tunnel`
4. If the change affects macOS packaging, mention:
   - tested architecture
   - whether signing/notarization was validated

### Development notes

- macOS release scripts live in [`macos-arm`](macos-arm)
- Build outputs and release artifacts must not be committed
- Do not commit secrets, certificates, provisioning profiles, private API tokens, or local absolute paths

## فارسی

ممنون بابت مشارکت.

قبل از باز کردن Pull Request:

1. برای تغییرات بزرگ اول issue باز کنید.
2. تغییرات را محدود و قابل review نگه دارید.
3. حالت درگیر را تست کنید:
   - `Proxy`
   - `Tunnel`
4. اگر تغییر مربوط به پکیجینگ macOS است، حتماً ذکر کنید:
   - روی چه معماری تست شده
   - آیا signing / notarization بررسی شده یا نه

### نکات توسعه

- اسکریپت‌های ریلیز macOS داخل [`macos-arm`](macos-arm) هستند
- فایل‌های build و artifact های release نباید commit شوند
- secret، certificate، provisioning profile، token، یا path شخصی local را commit نکنید
