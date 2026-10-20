# PdfCraft for Android

The PdfCraft app for Android, built as a regular Rust/eframe app packaged with
[cargo-apk](https://crates.io/crates/cargo-apk). It runs the same engine and egui shell as the
desktop app through wgpu (GLES by default, so it also works on old GPUs — `PDFCRAFT_VULKAN=1`
opts in to Vulkan), driven by `android-activity`. `mobile.rs` adds the mobile action bar and the
in-app file picker that stands in for `rfd` (no Android backend: `crates/ui-egui/src/rfd.rs`
queues each desktop picker and this app shows and answers it).

## Build

From the repository root, for each target (`aarch64-linux-android`, `x86_64-linux-android`,
`armv7-linux-androideabi`, `i686-linux-android`):

```sh
rustup target add aarch64-linux-android
cargo apk build -p pdfcraft-android --target aarch64-linux-android --release
```

`.github/workflows/pdfcraft-android.yml` builds and uploads the APK for all four targets.

## Files and permissions

The manifest asks for the media/scope-of-use of the desktop app (`android.permission.READ_MEDIA_IMAGES`,
`READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE` up to Android 12). PDFs outside the app's
sandbox additionally need **All files access** (Settings ▸ Apps ▸ PdfCraft): the in-app picker
says so when Android hides a folder from the app. The manifest declares
`android.permission.MANAGE_EXTERNAL_STORAGE` for the Settings toggle; it is never requested at
runtime, and reads that fail for lack of it surface as clear errors from the file picker.
