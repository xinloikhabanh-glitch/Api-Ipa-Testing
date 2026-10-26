# Touch Technology (iOS, Swift/SwiftUI)

App khoá bằng key (server Vercel) với 3 mục:
1. **Chức năng**: tình trạng máy (nhiệt độ, nguồn điện thấp, pin, bộ nhớ) kèm điểm "sẵn sàng chơi game", đo tốc độ lấy mẫu cảm ứng (Hz/ms/dao động), đo ping mạng, danh sách tối ưu iOS, trình phát nhạc (phát nền, hoà cùng âm thanh game).
2. **Độ nhạy FF**: tự nhận diện dòng iPhone/iPad, cho phép tìm dòng máy khác, gợi ý độ nhạy Free Fire theo màn hình + tần số quét + lối chơi.
3. **Admin**: Zalo, TikTok, thông tin key.

## Cấu trúc repo (đặt file ở THƯ MỤC GỐC, không cần thư mục con cho nhạc/icon)
```
project.yml
AppIcon.png                 (icon 1024x1024, tự chuyển thành icon app)
*.mp3                       (mọi file nhạc để ở gốc, app tự nhận)
Sources/App.swift
Sources/Features.swift
Sources/Sensitivity.swift
.github/workflows/build-ipa.yml
```
Thêm nhạc: upload thêm file .mp3/.m4a vào gốc repo rồi build lại. Đổi icon: upload AppIcon.png mới.
Thư mục `Web/` của bản cũ không còn dùng, có thể xoá.

## Build
Tab Actions → Build IPA → Run workflow → tải artifact `LicenseApp-ipa`. File .ipa chưa ký, cần ký bằng Sideloadly / AltStore / eSign / TrollStore.

## Giới hạn của iOS
App không thể tự đổi cảm ứng hay hiệu năng của game khác. Các công cụ ở đây đo thật và hướng dẫn chỉnh đúng cài đặt hệ thống.
Độ nhạy là gợi ý khởi điểm (công thức theo màn hình/tần số quét), không phải bảng chính thức của Free Fire.
