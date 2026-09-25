# Roadmap — Reviewer

Ứng dụng desktop Flutter cho giảng viên: chọn tài liệu requirement của sinh viên, phân tích cấu trúc, xem nội dung/hình ảnh theo từng mục, và đánh dấu đạt/chưa đạt.

## Đã xong

- Chọn tài liệu `.pdf` / `.doc` / `.docx` — `lib/widgets/document_uploader.dart`.
- Phân tích cấu trúc (heading/bookmark) thành cây:
  - `.docx` qua `w:outlineLvl` — `lib/services/docx_structure_parser.dart`.
  - `.pdf` qua bookmark (`pdfrx`), fallback theo trang nếu không có bookmark — `lib/services/pdf_structure_parser.dart`.
- Xem nội dung (text + hình ảnh) riêng của từng mục — `lib/services/docx_section_content_loader.dart`, `lib/services/pdf_section_content_loader.dart`.
- Đánh dấu Đạt/Chưa đạt + ghi chú theo từng mục, lưu vào thư mục dữ liệu của app (không đụng file gốc) — `lib/services/review_store.dart`, `lib/screens/review_screen.dart`.

## Đang làm / mới xong, cần người dùng xác nhận qua UI thật

Giai đoạn "trích xuất nội dung/hình ảnh + đánh dấu" vừa code xong, đã build/analyze sạch nhưng **chưa được người dùng bấm thử tay** với tài liệu thật (chọn mục, xem nội dung, đánh dấu, đóng mở lại app để kiểm tra có lưu không).

**AI kiểm tra toàn bộ tài liệu** (nút "AI kiểm tra" trên màn hình chấm) — gửi cả tài liệu cho AI và nhận về: nhận xét tổng quan, mục còn thiếu, danh sách vấn đề (mâu thuẫn, mơ hồ, không kiểm thử được, sơ đồ) gắn với từng mục; bấm để nhảy tới mục, hoặc "Thêm vào ghi chú". PDF gửi nguyên file (AI đọc cả chữ và hình trang); DOCX gửi text + ảnh theo từng mục. Kết quả lưu lại theo tài liệu — `lib/services/document_ai_reviewer.dart`, `lib/widgets/ai_review_panel.dart`.

**Cấu hình tại màn hình chọn tài liệu**:
- *Cấu hình AI* — chọn nhà cung cấp Anthropic (Claude) / OpenAI (GPT) / Google Gemini, API key và model riêng cho từng bên (trống thì dùng biến môi trường `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY`). Gọi thẳng HTTP vì Dart không có SDK chính thức — `lib/services/llm/`, `lib/widgets/ai_settings_dialog.dart`.
- *Mẫu cấu trúc tài liệu* — giảng viên soạn nhiều mẫu (mỗi dòng một mục, thụt lề = mục con, `?` = tuỳ chọn, sau `|` = yêu cầu nội dung), chọn mẫu dùng cho bài chấm; AI đối chiếu thiếu mục/sai cấu trúc theo mẫu thay vì IEEE 830 chung — `lib/models/structure_template.dart`, `lib/screens/structure_templates_screen.dart`.

**Chưa chạy thử với API key thật của cả ba nhà cung cấp** (định dạng request/response đã có unit test, nhưng chưa gọi API thật).

## Sắp tới (chưa làm)

- Xuất báo cáo tổng hợp kết quả chấm (PDF/Word/Excel) cho một tài liệu.
- Chấm nhiều tài liệu/nhiều sinh viên cùng lúc — cần màn hình quản lý danh sách bài nộp, không chỉ 1 file như hiện tại.
- Ảnh nhúng thật trong PDF (hiện chỉ chụp toàn trang do `pdfrx` không có API tách ảnh nhúng riêng lẻ) — cân nhắc thư viện khác nếu cần độ chính xác cao hơn.
- Hỗ trợ `.doc` (định dạng Word nhị phân cũ) — hiện báo lỗi yêu cầu chuyển sang `.docx`/PDF.
- Từ điển tiêu chí chấm (rubric) thay vì chỉ Đạt/Chưa đạt tự do.
