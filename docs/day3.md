# Day 3: File I/O, Redirection, Pipes, find, grep, sed, awk

> **هدف**: تسلط کامل بر کار با فایل‌ها، جستجو، فیلتر و ویرایش متن — ابزارهای روزانه DevOps

## 1. Redirection و Pipes
| عملگر | معنی | مثال |
|-------|------|------|
| `>`   | خروجی → فایل (overwrite) | `echo "hello" > file.txt` |
| `>>`  | خروجی → فایل (append) | `date >> log.txt` |
| `<`   | ورودی ← فایل | `mail -s "Hi" admin < body.txt` |
| `2>`  | خطا → فایل | `ls /root 2> error.log` |
| `&>`  | خروجی + خطا → فایل | `bash script.sh &> all.log` |
| `|`   | pipe | `ls -la \| grep ".sh"` |

## 2. کار با فایل‌ها
```bash
[ -f "file" ] && echo "exists"
[ -d "dir" ] && echo "is directory"
[ -r "file" ] && echo "readable"
[ -w "file" ] && echo "writable"
[ -x "file" ] && echo "executable"

## تمرین‌های پیاده‌سازی‌شده (همه تست‌شده)

| تمرین | اسکریپت | کاربرد واقعی |
|-------|--------|-------------|
| ۱ | `log-analyzer.sh` | تحلیل سریع لاگ‌های سیستم |
| ۲ | `backup-cleaner.sh` | مدیریت فضای بکاپ |
| ۳ | `user-report.sh` | گزارش امنیتی کاربران |
| ۴ | `find-large-files.sh` | پیدا کردن فایل‌های سنگین |
| ۵ | `nginx-access-top-ips.sh` | تشخیص حملات یا کاربران پرمصرف |

همه اسکریپت‌ها با `set -euo pipefail` و error handling مناسب نوشته شده‌اند.
