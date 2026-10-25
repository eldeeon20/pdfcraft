//! Bridge to the Kotlin shell for the orientation the Full/Window buttons lock.

use std::cell::RefCell;

use android_activity::AndroidApp;

thread_local! {
    static APP: RefCell<Option<AndroidApp>> = const { RefCell::new(None) };
}

/// Keeps a handle to the activity so the UI thread can post orientation changes to Java.
pub fn install(app: AndroidApp) {
    APP.with(|slot| {
        if let Ok(mut slot) = slot.try_borrow_mut() {
            *slot = Some(app);
        }
    });
}

/// Viewer (full screen) locks portrait; editor (window) locks landscape.
pub fn set_viewer_mode(on: bool) {
    APP.with(|slot| {
        let Ok(slot) = slot.try_borrow() else { return; };
        let Some(app) = slot.as_ref() else { return; };
        app.run_on_java_main_thread(Box::new(move || {
            let Ok(vm) = jni::JavaVM::singleton() else { return; };
            let _ = vm.with_top_local_frame(|env| -> jni::errors::Result<()> {
                let class = jni::strings::JNIString::new("ai/storyteller/pdfcraft/KotlinBridge");
                let name = jni::strings::JNIString::new("setViewerMode");
                let Ok(sig) = "(Z)V".parse::<jni::signature::RuntimeMethodSignature>() else {
                    return Ok(());
                };
                let sig = sig.method_signature();
                env.call_static_method(
                    &class,
                    &name,
                    &sig,
                    &[jni::objects::JValue::Bool(on)],
                )?;
                Ok(())
            });
        }));
    });
}
