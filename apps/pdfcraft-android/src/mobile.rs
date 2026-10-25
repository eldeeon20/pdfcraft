//! Android mobile shell: the top action bar, full-screen escape and the in-app file picker.
//!
//! rfd has no Android backend, so the `rfd::` shim in ui-egui queues each desktop picker as a
//! [`PendingPick`], which the in-app picker here renders and answers: `pickers.rs` waits for the
//! reply on a worker thread and uses the chosen paths on the next frame like any other pick.
//! Files are read and written through the file system, so opening a PDF outside the app sandbox
//! needs "All files access" (Settings ▸ Apps ▸ PdfCraft); until it is granted the picker says so.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use egui::{Align, Align2, Frame, Margin, RichText, ScrollArea, Stroke, vec2};
use pdfcraft_ui_egui::theme::Tokens;
use pdfcraft_ui_egui::{PdfCraftApp, SaveTarget};
use pdfcraft_ui_egui::rfd::{PendingKind, PendingPick, take_pending};

/// Overlays and window state shared between the runner's frames.
#[derive(Default)]
pub struct MobileState {
    pub full_screen: bool,
    /// Last orientation seen (true = portrait). `None` until the first frame, so the
    /// automatic Full/Window switch runs once on startup and again on every rotation.
    pub(crate) portrait: Option<bool>,
    /// Set by the Full/Window buttons: from then on the chosen mode owns the orientation.
    pub(crate) locked: bool,
    /// Whether a document was open last frame, so opening one in portrait enters the
    /// viewer even when the device did not rotate.
    pub(crate) document_open: bool,
    picker: Option<Picker>,
}

pub type SharedMobileState = Arc<Mutex<MobileState>>;

/// One pending pick being shown; dropped when the pick is answered.
struct Picker {
    pending: PendingPick,
    dir: PathBuf,
    /// The current folder's folders and the files this pick's filters allow, folders first.
    entries: Vec<(String, bool)>,
    listing_err: Option<String>,
    chosen: Vec<String>,
    file_name: String,
    answered: bool,
}

/// Phone-scale widgets: bigger touch targets (photocraft's Android PR does the same).
pub fn configure_mobile_style(style: &mut egui::Style) {
    style.spacing.interact_size = vec2(44.0, 38.0);
}

/// The action bar: Open, Save and the reading toggles.
pub fn render_action_bar(app: &mut PdfCraftApp, ui: &mut egui::Ui, state: &mut MobileState) {
    let ctx = ui.ctx().clone();
    let t = Tokens::get(&ctx);
    egui::Panel::top("pdfcraft_mobile_action_bar")
        .exact_size(44.0)
        .frame(Frame::NONE.fill(t.panel).inner_margin(Margin::symmetric(10, 4)))
        .show(ui, |ui| {
            ui.with_layout(egui::Layout::left_to_right(Align::Center), |ui| {
                bar_button(ui, &t, "📂 Open", || app.open_dialog());
                bar_button(ui, &t, "💾 Save", || save_active(app));
                bar_button(ui, &t, "☰ Panel", || app.left_open = !app.left_open);
                bar_button(ui, &t, "⛶ Full", || set_full_screen(app, &ctx, state, true, true));
            });
        });
}

/// File ▸ Save. PdfCraft itself reports save failures and asks where (the picker shows there).
fn save_active(app: &mut PdfCraftApp) {
    app.save_active(SaveTarget::InPlace);
}

fn bar_button(ui: &mut egui::Ui, t: &Tokens, label: &str, action: impl FnOnce()) {
    let button = egui::Button::new(RichText::new(label).color(t.text))
        .fill(t.panel)
        .min_size(vec2(0.0, 36.0));
    if ui.add(button).clicked() {
        action();
    }
}

/// Enter or leave full-screen reading (Acrobat: View ▸ Full Screen Mode).
///
/// `lock_orientation` is true for the buttons: viewer locks portrait, window locks
/// landscape, so the editor controls always have room. The automatic orientation on
/// startup/rotation passes false and leaves the device free.
pub fn set_full_screen(
    app: &mut PdfCraftApp,
    ctx: &egui::Context,
    state: &mut MobileState,
    on: bool,
    lock_orientation: bool,
) {
    // Full-screen reading is meaningless on the home screen: it would hide the action
    // bar and lock the orientation with nothing to read.
    if on && !app.has_document() {
        return;
    }
    state.full_screen = on;
    app.set_full_screen(ctx, on);
    app.set_viewer_mode(on);
    if lock_orientation {
        state.locked = true;
        crate::orientation::set_viewer_mode(on);
    }
}

/// The way out of full-screen reading: back to the home screen, with automatic
/// orientation still enabled (rotating can enter the editor again).
pub fn render_fullscreen_exit(app: &mut PdfCraftApp, ctx: &egui::Context, state: &mut MobileState) {
    let t = Tokens::get(ctx);
    egui::Area::new(egui::Id::new("pdfcraft_fullscreen_exit"))
        .anchor(Align2::LEFT_TOP, [14.0, 14.0])
        .order(egui::Order::Foreground)
        .show(ctx, |ui| {
            Frame::NONE
                .fill(t.card)
                .stroke(Stroke::new(1.0, t.border))
                .corner_radius(egui::CornerRadius::same(10))
                .inner_margin(Margin::same(4))
                .show(ui, |ui| {
                    ui.horizontal(|ui| {
                        if ui.add(egui::Button::new("← Volver").min_size(vec2(0.0, 36.0))).clicked() {
                            leave_viewer_to_home(app, ctx, state);
                        }
                        if ui.add(egui::Button::new("📂 Abrir").min_size(vec2(0.0, 36.0))).clicked() {
                            app.open_dialog();
                        }
                    });
                });
        });
}

/// Close the document and return to the home screen without locking the orientation.
/// `portrait` is kept current so the automatic Full/Window switch does not immediately
/// re-enter full-screen before the user rotates the device.
fn leave_viewer_to_home(app: &mut PdfCraftApp, ctx: &egui::Context, state: &mut MobileState) {
    let portrait = ctx.content_rect().width() <= ctx.content_rect().height();
    state.full_screen = false;
    state.locked = false;
    state.portrait = Some(portrait);
    app.set_full_screen(ctx, false);
    app.set_viewer_mode(false);
    app.left_open = false;
    app.right = None;
    app.close_all();
}

/// Shows and answers the queued rfd picks, one at a time.
pub fn render_picker(ctx: &egui::Context, state: &mut MobileState) {
    if state.picker.is_none() {
        if let Some(pending) = take_pending() {
            state.picker = Some(Picker::new(pending));
        }
        return;
    }
    let Some(mut picker) = state.picker.take() else { return };
    let t = Tokens::get(ctx);
    let mut open = true;
    egui::Window::new(picker.title())
        .open(&mut open)
        .collapsible(false)
        .resizable(false)
        .order(egui::Order::Foreground)
        .anchor(Align2::CENTER_CENTER, [0.0, 0.0])
        .fixed_size(vec2(ctx.content_rect().width().min(420.0), ctx.content_rect().height().min(520.0)))
        .frame(Frame::NONE.fill(t.card).stroke(Stroke::new(1.0, t.border)).inner_margin(Margin::same(10)))
        .show(ctx, |ui| picker.body(ui));
    if !open {
        // The dialog's close button: a cancel.
        picker.answer(None);
    }
    if picker.answered {
        // Let the awaiting worker thread see the result and the app act on the pick.
        ctx.request_repaint();
    } else {
        state.picker = Some(picker);
        ctx.request_repaint();
    }
}

impl Picker {
    fn new(pending: PendingPick) -> Self {
        let file_name = pending.file_name.clone().unwrap_or_default();
        let mut me = Self { pending, dir: default_dir(), entries: Vec::new(), listing_err: None, chosen: Vec::new(), file_name, answered: false };
        me.list();
        me
    }

    /// The in-app dialog's heading.
    fn title(&self) -> String {
        match &self.pending.kind {
            PendingKind::Files { .. } => self.pending.title.clone().unwrap_or_else(|| "Choose a file".into()),
            PendingKind::Folder => self.pending.title.clone().unwrap_or_else(|| "Choose a folder".into()),
            PendingKind::Save => self.pending.title.clone().unwrap_or_else(|| "Save as".into()),
        }
    }

    /// Whether a file name passes this pick's filters (folder and save picks take everything).
    fn allowed(&self, name: &str) -> bool {
        if matches!(self.pending.kind, PendingKind::Folder | PendingKind::Save) {
            return false;
        }
        let ext_of = |name: &str| Path::new(name).extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
        self.pending.filters.is_empty() || self.pending.filters.iter().any(|(_, exts)| exts.iter().any(|e| *e == ext_of(name)))
    }

    /// Reads `dir` into `entries`: folders first, then files, each alphabetically.
    fn list(&mut self) {
        self.entries.clear();
        self.listing_err = None;
        match std::fs::read_dir(&self.dir) {
            Ok(dir) => {
                let mut directories = Vec::new();
                let mut files = Vec::new();
                for entry in dir.flatten() {
                    let is_dir = entry.file_type().map(|f| f.is_dir()).unwrap_or(false);
                    let name = entry.file_name().to_string_lossy().into_owned();
                    if name.starts_with('.') {
                        continue;
                    }
                    if is_dir {
                        directories.push(name);
                    } else if self.allowed(&name) {
                        files.push(name);
                    }
                }
                directories.sort();
                files.sort();
                self.entries = directories.into_iter().map(|n| (n, true)).chain(files.into_iter().map(|n| (n, false))).collect();
            }
            Err(e) => {
                self.listing_err = Some(format!(
                    "PdfCraft can't read {folder}: grant it \"All files access\" in Settings ▸ Apps ▸ PdfCraft.",
                    folder = self.dir.display()
                ));
                log::warn!("reading {}: {e}", self.dir.display());
            }
        }
        self.chosen.retain(|name| Path::new(&name).is_file());
    }

    fn answer(&mut self, paths: Option<Vec<PathBuf>>) {
        if self.answered {
            return;
        }
        self.answered = true;
        self.pending.answer(paths);
    }

    fn body(&mut self, ui: &mut egui::Ui) {
        let t = Tokens::get(ui.ctx());
        let multiple = matches!(self.pending.kind, PendingKind::Files { multiple: true });

        // The current folder and the way up.
        ui.horizontal(|ui| {
            ui.label(RichText::new(self.dir.display().to_string()).color(t.text_muted).small());
            if ui.add(egui::Button::new("⬆").min_size(vec2(0.0, 32.0))).clicked() {
                if let Some(parent) = self.dir.parent() {
                    self.dir = parent.to_path_buf();
                    self.list();
                }
            }
        });

        // The folders everyone knows first: Downloads, Documents, Pictures.
        for (label, dir) in shortcuts() {
            if !dir.is_dir() {
                continue;
            }
            if ui.add(egui::Button::new(RichText::new(label).color(t.accent).small())).clicked() {
                self.dir = dir;
                self.list();
            }
        }
        ui.separator();

        if let Some(err) = &self.listing_err {
            ui.label(RichText::new(err).color(t.accent_text).small());
        }
        if !all_files_access() && self.dir.starts_with("/storage/emulated/0/") {
            let hidden = "Other apps' PDFs stay hidden until PdfCraft has \"All files access\" (Settings ▸ Apps ▸ PdfCraft).";
            ui.label(RichText::new(hidden).color(t.text_muted).small());
        }

        let mut navigated = false;
        ScrollArea::vertical().max_height(ui.available_height() - 96.0).auto_shrink([false; 2]).show(ui, |ui| {
            for (name, is_dir) in self.entries.clone() {
                let text = if is_dir { format!("📁 {name}") } else { name.clone() };
                let selected = self.chosen.contains(&name);
                if ui.selectable_label(selected, RichText::new(text).color(t.text)).clicked() {
                    if is_dir {
                        self.dir = self.dir.join(name);
                        self.chosen.clear();
                        self.list();
                        navigated = true;
                        break;
                    } else if multiple {
                        if selected {
                            self.chosen.retain(|c| *c != name);
                        } else {
                            self.chosen.push(name.clone());
                        }
                    } else {
                        self.chosen = vec![name.clone()];
                    }
                }
            }
        });
        if navigated {
            return;
        }

        match self.pending.kind {
            PendingKind::Files { multiple } => {
                let label = if multiple && self.chosen.len() > 1 { format!("Open {} files", self.chosen.len()) } else { "Open".into() };
                if !multiple {
                    self.chosen.truncate(1);
                }
                if ui.add_enabled(!self.chosen.is_empty(), egui::Button::new(label)).clicked() {
                    let paths = self.chosen.iter().map(|n| self.dir.join(n)).collect::<Vec<_>>();
                    self.answer(Some(paths));
                    return;
                }
            }
            PendingKind::Folder => {
                let hint = self.chosen.first().map(|n| self.dir.join(n)).unwrap_or_else(|| self.dir.clone());
                let name = hint.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| hint.display().to_string());
                if ui.add(egui::Button::new(format!("Choose {name}")).min_size(vec2(0.0, 36.0))).clicked() {
                    self.answer(Some(vec![hint]));
                    return;
                }
            }
            PendingKind::Save => {
                ui.add(egui::TextEdit::singleline(&mut self.file_name).hint_text("File name"));
                if ui.add_enabled(!self.file_name.trim().is_empty(), egui::Button::new("Save")).clicked() {
                    let name = self.file_name.trim().to_string();
                    self.answer(Some(vec![self.dir.join(name)]));
                    return;
                }
            }
        }
        if ui.add(egui::Button::new("Cancel")).clicked() {
            self.answer(None);
            return;
        }
    }
}

/// The FUSE daemon keeps `/storage/emulated/0/Android/data` (other apps' data) behind "All files
/// access"; a readable listing there means PdfCraft has it and can see every PDF on shared storage.
fn all_files_access() -> bool {
    std::fs::read_dir("/storage/emulated/0/Android/data").map(|mut d| d.next().is_some()).unwrap_or(false)
}

/// The storage shortcuts, where most documents live on a phone.
fn shortcuts() -> Vec<(&'static str, PathBuf)> {
    let storage = PathBuf::from("/storage/emulated/0");
    vec![("Download", storage.join("Download")), ("Documents", storage.join("Documents")), ("Pictures", storage.join("Pictures"))]
}

/// `/storage/emulated/0/Download` on the common Android installs; `/storage` when it isn't there.
fn default_dir() -> PathBuf {
    let storage = PathBuf::from("/storage/emulated/0");
    let download = storage.join("Download");
    if download.is_dir() {
        return download;
    }
    if storage.is_dir() {
        return storage;
    }
    PathBuf::from("/")
}
