//! PdfCraft on Android.
//!
//! Runs the engine and egui shell through eframe's Android runner (wgpu on GLES by default,
//! driven by `android-activity`). The mobile bits live in `mobile.rs`: the top action bar, the
//! full-screen escape and the in-app file picker that stands in for `rfd` (no Android backend:
//! see `crates/ui-egui/src/rfd.rs`).

#![deny(unsafe_code)]
#![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]

#[cfg(target_os = "android")]
mod android_app;
#[cfg(target_os = "android")]
mod mobile;
#[cfg(target_os = "android")]
mod orientation;

#[cfg(target_os = "android")]
// SAFETY: Required by android-activity to export the C entry point for Android NativeActivity.
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
fn android_main(app: android_activity::AndroidApp) {
    android_app::start(app);
}

/// Whether this build is compiled for Android.
pub fn is_android_target() -> bool {
    cfg!(target_os = "android")
}
