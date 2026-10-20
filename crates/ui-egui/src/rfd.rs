//! File picker entry points, shared by every crate file.
//!
//! On native targets (desktop, wasm32) this forwards the real `rfd`, renamed locally to
//! `rfd_native` so the same `rfd::` paths keep working everywhere; on Android, where rfd has no
//! backend, it is an in-app picker shim: `pick_file`/`save_file`/… queue a `PendingPick` and
//! still return a future the desktop code paths await; the Android runner
//! (`apps/pdfcraft-android`) shows and resolves it in its own file picker (see `pickers.rs`).

#[cfg(not(target_os = "android"))]
pub use rfd_native::*;

#[cfg(target_os = "android")]
mod mobile {
    use std::future::Future;
    use std::path::{Path, PathBuf};
    use std::pin::Pin;
    use std::sync::{Arc, Mutex, PoisonError};
    use std::task::{Context, Poll, Waker};

    pub type DialogFutureType<T> = Pin<Box<dyn Future<Output = T> + Send>>;

    /// A queued dialog; the Android runner surfaces it in its own file picker and resolves the
    /// reply (one `take_pending()` per future).
    pub struct PendingPick {
        pub kind: PendingKind,
        pub title: Option<String>,
        pub file_name: Option<String>,
        pub filters: Vec<(String, Vec<String>)>,
        pub reply: Replier,
    }

    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    pub enum PendingKind {
        Files { multiple: bool },
        Folder,
        Save,
    }

    #[derive(Debug)]
    pub struct FileHandle(PathBuf);

    impl FileHandle {
        pub fn path(&self) -> &Path {
            &self.0
        }
    }

    #[derive(Clone, Debug, Default)]
    pub struct AsyncFileDialog {
        title: Option<String>,
        file_name: Option<String>,
        filters: Vec<(String, Vec<String>)>,
    }

    impl AsyncFileDialog {
        pub fn new() -> Self {
            Self::default()
        }

        pub fn set_title(mut self, title: impl Into<String>) -> Self {
            self.title = Some(title.into());
            self
        }

        pub fn set_file_name(mut self, file_name: impl Into<String>) -> Self {
            self.file_name = Some(file_name.into());
            self
        }

        pub fn add_filter(mut self, name: impl Into<String>, extensions: &[&str]) -> Self {
            self.filters.push((
                name.into(),
                extensions.iter().map(|e| e.trim_start_matches('.').to_lowercase()).collect(),
            ));
            self
        }

        pub fn pick_file(self) -> DialogFutureType<Option<FileHandle>> {
            Box::pin(async move {
                one(ask(self, PendingKind::Files { multiple: false }).await?)
            })
        }

        pub fn pick_files(self) -> DialogFutureType<Option<Vec<FileHandle>>> {
            Box::pin(async move {
                Some(ask(self, PendingKind::Files { multiple: true }).await?.into_iter().map(FileHandle).collect())
            })
        }

        pub fn pick_folder(self) -> DialogFutureType<Option<FileHandle>> {
            Box::pin(async move { one(ask(self, PendingKind::Folder).await?) })
        }

        pub fn save_file(self) -> DialogFutureType<Option<FileHandle>> {
            Box::pin(async move { one(ask(self, PendingKind::Save).await?) })
        }
    }

    fn one(paths: Vec<PathBuf>) -> Option<FileHandle> {
        paths.into_iter().next().map(FileHandle)
    }

    type Reply = Arc<Share<Option<Vec<PathBuf>>>>;

    struct Share<T> {
        value: Mutex<Option<T>>,
        waker: Mutex<Option<Waker>>,
    }

    struct Replier(Reply);

    impl Replier {
        pub fn send(self, paths: Option<Vec<PathBuf>>) {
            let Share { value, waker } = &*self.0;
            {
                let mut value = value.lock().unwrap_or_else(PoisonError::into_inner);
                *value = paths;
            }
            let waker = {
                let mut waker = waker.lock().unwrap_or_else(PoisonError::into_inner);
                waker.take()
            };
            if let Some(waker) = waker {
                waker.wake();
            }
        }
    }

    struct ShareReply(Reply);

    impl Future for ShareReply {
        type Output = Option<Vec<PathBuf>>;
        fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
            let Share { value, waker } = &*self.0;
            let mut value = value.lock().unwrap_or_else(PoisonError::into_inner);
            if let Some(paths) = value.take() {
                return Poll::Ready(paths);
            }
            let mut waker = waker.lock().unwrap_or_else(PoisonError::into_inner);
            *waker = Some(cx.waker().clone());
            Poll::Pending
        }
    }

    static PENDING: Mutex<Option<PendingPick>> = Mutex::new(None);

    pub fn take_pending() -> Option<PendingPick> {
        PENDING.lock().unwrap_or_else(PoisonError::into_inner).take()
    }

    async fn ask(dialog: AsyncFileDialog, kind: PendingKind) -> Option<Vec<PathBuf>> {
        let share = Arc::new(Share { value: Mutex::new(None), waker: Mutex::new(None) });
        let pending = PendingPick { kind, title: dialog.title, file_name: dialog.file_name, filters: dialog.filters, reply: Replier(share.clone()) };
        {
            let mut slot = PENDING.lock().unwrap_or_else(PoisonError::into_inner);
            // The Android file picker can only show one dialog: an older one still up is
            // cancelled when a new request arrives.
            if let Some(pending) = slot.take() {
                pending.reply.send(None);
            }
            *slot = Some(pending);
        }
        ShareReply(share).await
    }
}

#[cfg(target_os = "android")]
pub use mobile::*;
