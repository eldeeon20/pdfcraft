//! Android application runtime and eframe runner setup.

use std::path::PathBuf;

use pdfcraft_ui_egui::PdfCraftApp;

use crate::mobile;

/// Starts the PdfCraft Android runner.
pub fn start(android_app: android_activity::AndroidApp) {
    let internal_path = android_app.internal_data_path().map(PathBuf::from);

    let mut options = eframe::NativeOptions::default();
    options.android_app = Some(android_app);
    // Settings and crash recovery stay in the app sandbox (`main.rs` keeps them in the user's
    // home; there isn't one on Android).
    options.persistence_path = internal_path.clone().map(|d| d.join("PdfCraft").join("app.ron"));

    // On Android, use GLES backend by default to avoid ANativeWindow double-binding crashes
    // when probing Vulkan on emulators, Waydroid, and older GPUs.
    if let eframe::egui_wgpu::WgpuSetup::CreateNew(setup) = &mut options.wgpu_options.wgpu_setup {
        let use_vulkan = std::env::var("PDFCRAFT_VULKAN").map(|v| v == "1" || v == "true").unwrap_or(false);
        if use_vulkan {
            setup.instance_descriptor.backends = eframe::wgpu::Backends::VULKAN;
        } else {
            setup.instance_descriptor.backends = eframe::wgpu::Backends::GL;
        }
    }

    let result = eframe::run_native(
        "PdfCraft",
        options,
        Box::new(move |cc| {
            let mut app = PdfCraftApp::new();
            if let Some(json) = cc.storage.as_ref().and_then(|s| s.get_string("pdfcraft")) {
                app.restore(&json);
            }
            // A PDF chosen with the system picker (Kotlin side) is dropped here before the
            // UI starts, so the original shell just opens it like any recent document.
            if let Some(dir) = internal_path.as_deref() {
                open_pending_pick(dir, &mut app);
            }

            cc.egui_ctx.global_style_mut(mobile::configure_mobile_style);

            // A collapsed left panel and a plain viewport fit a phone; the action bar comes
            // back when full-screen reading ends.
            app.left_open = false;
            app.integrated_titlebar = false;
            // A phone is not a desktop: comments/bookmarks would cover the page, so they don't
            // pop open on their own and a restored panel starts closed.
            app.auto_open_panels = false;
            app.right = None;
            pdfcraft_ui_egui::theme::set_mobile(true);

            // Autosave unsaved changes; offer to recover documents a crashed session left behind.
            if let Some(dir) = internal_path.clone() {
                app.enable_recovery(pdfcraft_ui_egui::RecoveryStore::new(dir.join("PdfCraft").join("Recovery")));
            }

            if let Some(rs) = cc.wgpu_render_state.clone() {
                let info = rs.adapter.get_info();
                log::info!("pdfcraft-android: wgpu backend {:?} on {}", info.backend, info.name);
            }

            let state = mobile::SharedMobileState::default();
            Ok(Box::new(MobileShell { app, state }))
        }),
    );

    if let Err(e) = result {
        log::error!("pdfcraft-android: failed to run: {e}");
    }
}

/// The PdfCraft shell with the mobile action bar and file picker on top.
struct MobileShell {
    app: PdfCraftApp,
    state: mobile::SharedMobileState,
}

impl eframe::App for MobileShell {
    fn logic(&mut self, ctx: &egui::Context, frame: &mut eframe::Frame) {
        self.app.logic(ctx, frame);
    }

    fn ui(&mut self, ui: &mut egui::Ui, frame: &mut eframe::Frame) {
        let ctx = ui.ctx().clone();
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());

        // 1. Mobile action bar (hidden during full-screen reading).
        if !state.full_screen {
            mobile::render_action_bar(&mut self.app, ui, &mut state);
        }

        // 2. Canvas, panels, dialogs: the app renders itself.
        self.app.ui(ui, frame);

        // 3. The in-app file picker, and the way back out of full screen.
        mobile::render_picker(&ctx, &mut state);
        if state.full_screen {
            mobile::render_fullscreen_exit(&mut self.app, &ctx, &mut state);
        }
    }
}

/// Opens (once) the document a SAF pick left for us in the app sandbox.
fn open_pending_pick(dir: &std::path::Path, app: &mut PdfCraftApp) {
    let marker = dir.join("PdfCraft").join("pending_open.txt");
    let Ok(path) = std::fs::read_to_string(&marker) else { return; };
    let _ = std::fs::remove_file(&marker);
    let path = path.trim();
    if !path.is_empty() {
        app.open_path(path);
    }
}
