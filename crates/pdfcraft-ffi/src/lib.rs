//! pdfcraft-ffi — thin C ABI over the engine facade for the scripted Android app.
//!
//! Protocol:
//! - `pdfcraft_call(request bytes) -> JSON bytes` (free the result with `pdfcraft_free`).
//!   Every request is `{"m": "<method>", ...}`; every answer is `{"ok": true, ...}` or
//!   `{"ok": false, "err": "why"}`.
//! - `pdfcraft_image(doc, page, dpi) -> PNG bytes` (free with `pdfcraft_free`).
//! - A panicking operation is caught and reported, never aborted.
#![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]

use std::sync::{Mutex, OnceLock};

use pdfcraft_engine::{DocId, Edit, Session};

type SessionSlot = OnceLock<Mutex<Session>>;

fn session_slot() -> &'static Mutex<Session> {
    static SLOT: SessionSlot = OnceLock::new();
    SLOT.get_or_init(|| Mutex::new(Session::new()))
}

const FFI_VERSION: u64 = 1;

// ---------------------------------------------------------------- ABI

/// Sanity pin: the Dart host checks this before anything else.
#[unsafe(no_mangle)]
pub extern "C" fn pdfcraft_ping() -> u64 {
    FFI_VERSION
}

/// JSON-in, JSON-out. `req` is a UTF-8 JSON object, `len` its byte length.
/// Returns a freshly allocated UTF-8 JSON result (length written to `out_len`), owned
/// by the caller: give it back with [`pdfcraft_free`]. Null only if the request was
/// unreadable.
#[unsafe(no_mangle)]
pub extern "C" fn pdfcraft_call(req: *const u8, len: u32, out_len: *mut u32) -> *mut u8 {
    let answer = run(req, len);
    let bytes = answer.into_bytes();
    let n = bytes.len();
    if n > u32::MAX as usize {
        return std::ptr::null_mut();
    }
    let ptr = Box::into_raw(bytes.into_boxed_slice()) as *mut u8;
    if !out_len.is_null() {
        unsafe { out_len.write(n as u32) };
    }
    ptr
}

/// The last rendered page, straight from [`pdfcraft_image`]: one slot, one consumer.
#[unsafe(no_mangle)]
pub extern "C" fn pdfcraft_image(doc: u64, page: u32, dpi: f64, out_len: *mut u32) -> *mut u8 {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let guard = session_slot().lock().map(|mut s| s.get_doc_png(DocId(doc), page, dpi));
        match guard {
            Ok(Ok(bytes)) => bytes,
            Ok(Err(e)) => error_bytes(&e),
            Err(_) => error_bytes("rendering failed unexpectedly"),
        }
    }))
    .unwrap_or_else(|_| error_bytes("rendering crashed"));
    let n = result.len().min(u32::MAX as usize);
    let ptr = Box::into_raw(result.into_boxed_slice()) as *mut u8;
    if !out_len.is_null() {
        unsafe { out_len.write(n as u32) };
    }
    ptr
}

/// Frees what [`pdfcraft_call`] or [`pdfcraft_image`] returned.
#[unsafe(no_mangle)]
pub extern "C" fn pdfcraft_free(ptr: *mut u8, len: u32) {
    if ptr.is_null() {
        return;
    }
    let slice = unsafe { std::slice::from_raw_parts(ptr, len as usize) };
    let boxed = unsafe { Box::from_raw(slice as *const [u8] as *mut [u8]) };
    drop(boxed);
}

fn error_bytes(why: &str) -> Vec<u8> {
    serde_json::json!({ "ok": false, "err": why }).to_string().into_bytes()
}

// ---------------------------------------------------------------- dispatch

fn doc(pages_count: usize) -> serde_json::Value {
    serde_json::json!({ "pages": pages_count })
}

fn run(req: *const u8, len: u32) -> String {
    let req = unsafe { std::slice::from_raw_parts(req, len as usize) };
    let parsed: serde_json::Value = match serde_json::from_slice(req) {
        Ok(v) => v,
        Err(e) => return answer(Err(format!("unreadable request ({e})"))),
    };
    let method = parsed.get("m").and_then(|m| m.as_str()).unwrap_or_default().to_owned();
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| dispatch(&method, &parsed)));
    match outcome {
        Ok(Ok(v)) => answer(Ok(v)),
        Ok(Err(e)) => answer(Err(e)),
        Err(_) => answer(Err(format!("{method} failed unexpectedly"))),
    }
}

fn answer(r: Result<serde_json::Value, String>) -> String {
    match r {
        Ok(extra) => {
            let mut v = serde_json::json!({ "ok": true });
            if let Some(obj) = extra.as_object() {
                for (k, val) in obj {
                    v[k.as_str()] = val.clone();
                }
            }
            v.to_string()
        }
        Err(e) => serde_json::json!({ "ok": false, "err": e }).to_string(),
    }
}

fn dispatch(m: &str, v: &serde_json::Value) -> Result<serde_json::Value, String> {
    match m {
        "version" => Ok(serde_json::json!({ "version": FFI_VERSION })),
        "open" => open_path(v),
        "create" => create_text(v),
        "pages" => page_count(v),
        "rotate" => page_arg_edit(v, "pages", |pages| {
            let deg = v.get("deg").and_then(|d| d.as_i64()).unwrap_or(90);
            Edit::RotatePages { pages, degrees: deg }
        }),
        "delete" => page_arg_edit(v, "pages", |pages| Edit::DeletePages { pages }),
        "move" => {
            let to = v_num(v, "to")? as usize;
            page_arg_edit(v, "pages", |pages| Edit::MovePages { pages, to })
        }
        "duplicate" => page_arg_edit(v, "pages", |pages| {
            let at = v.get("at").and_then(|a| a.as_u64()).map(|a| a as usize);
            Edit::DuplicatePages { pages, at }
        }),
        "blank" => {
            let doc = v_docid(v)?;
            let at = v_num(v, "at")? as usize;
            let (w, h) = (v_f64(v, "w").unwrap_or(612.0), v_f64(v, "h").unwrap_or(792.0));
            do_apply(doc, Edit::InsertBlankPage { at, width: w, height: h })
        }
        "undo" => simple_session(v, |s, id| s.undo(id).map_err(|e| e.to_string()).map(|label| serde_json::json!({ "label": label.to_string(), "pages": s.page_len(id) }))),
        "redo" => simple_session(v, |s, id| s.redo(id).map_err(|e| e.to_string()).map(|label| serde_json::json!({ "label": label.to_string(), "pages": s.page_len(id) }))),
        "save" => save_doc(v),
        "close" => {
            let id = v_docid(v)?;
            let mut s = session_slot().lock().map_err(|_| "session poisoned".to_string())?;
            s.close(id);
            Ok(serde_json::json!({}))
        }
        _ => Err(format!("unknown method '{m}'")),
    }
}

// ---------------------------------------------------------------- ops

trait PagesLen {
    fn page_len(&self, id: DocId) -> usize;
}

impl PagesLen for Session {
    fn page_len(&self, id: DocId) -> usize {
        self.get(id).map(|d| d.info.pages.len()).unwrap_or_default()
    }
}

fn sess() -> Result<&'static Mutex<Session>, String> {
    Ok(session_slot())
}

fn with<T>(f: impl FnOnce(&mut Session) -> Result<T, String>) -> Result<T, String> {
    let mut s = sess()?.lock().map_err(|_| "session poisoned".to_string())?;
    f(&mut s)
}

trait GetDocPng {
    fn get_doc_png(&mut self, id: DocId, page: u32, dpi: f64) -> Result<Vec<u8>, String>;
}

impl GetDocPng for Session {
    fn get_doc_png(&mut self, id: DocId, page: u32, dpi: f64) -> Result<Vec<u8>, String> {
        use pdfcraft_engine::export::Exporter;
        let doc = self.get(id).ok_or(format!("no document {}", id.0))?;
        let mut exp = Exporter::new(doc);
        exp.png(page as usize, dpi)
    }
}

trait DoApply {
    fn do_apply(&mut self, id: DocId, edit: Edit) -> Result<(), String>;
}

impl DoApply for Session {
    fn do_apply(&mut self, id: DocId, edit: Edit) -> Result<(), String> {
        self.apply(id, edit).map_err(|e| e.to_string())
    }
}

fn do_apply(id: DocId, edit: Edit) -> Result<serde_json::Value, String> {
    with(|s| {
        s.do_apply(id, edit)?;
        Ok(doc(s.page_len(id)))
    })
}

fn v_num(v: &serde_json::Value, key: &str) -> Result<i64, String> {
    v.get(key)
        .and_then(|x| x.as_i64())
        .or_else(|| v.get(key).and_then(|x| x.as_f64()).map(|f| f as i64))
        .ok_or(format!("missing integer '{key}'"))
}

fn v_f64(v: &serde_json::Value, key: &str) -> Result<f64, String> {
    v.get(key).and_then(|x| x.as_f64()).ok_or(format!("missing number '{key}'"))
}

fn v_docid(v: &serde_json::Value) -> Result<DocId, String> {
    Ok(DocId(v_num(v, "doc")? as u64))
}

fn open_path(v: &serde_json::Value) -> Result<serde_json::Value, String> {
    let path = v.get("path").and_then(|p| p.as_str()).ok_or("missing 'path'")?;
    let bytes = std::fs::read(path).map_err(|e| format!("reading '{path}' failed ({e})"))?;
    open_bytes(&bytes, path)
}

fn open_bytes(bytes: &[u8], name: &str) -> Result<serde_json::Value, String> {
    let display = name.split(['/', '\\']).next_back().unwrap_or("document.pdf").to_owned();
    with(|s| {
        let id = s.open(display.clone(), None, std::sync::Arc::new(bytes.to_vec()), None).map_err(|e| e.to_string())?;
        let got = s.get(id).ok_or("document opened then vanished")?;
        let info = &got.info;
        Ok(serde_json::json!({
            "doc": id.0,
            "pages": info.pages.len(),
            "title": info.title.clone().unwrap_or_else(|| display.trim_end_matches(".pdf").to_string()),
            "encrypted": info.encrypted,
        }))
    })
}

fn create_text(v: &serde_json::Value) -> Result<serde_json::Value, String> {
    let title = v.get("title").and_then(|t| t.as_str()).ok_or("missing 'title'")?;
    let text = v.get("text").and_then(|t| t.as_str()).ok_or("missing 'text'")?;
    with(|s| {
        let bytes = s.create_from_text(title, text).map_err(|e| e.to_string())?;
        let id = s.open_new(format!("{title}.pdf"), bytes).map_err(|e| e.to_string())?;
        Ok(serde_json::json!({ "doc": id.0, "pages": s.page_len(id) }))
    })
}

fn page_count(v: &serde_json::Value) -> Result<serde_json::Value, String> {
    let id = v_docid(v)?;
    let n = with(|s| Ok(s.page_len(id)))?;
    Ok(doc(n))
}

fn page_arg_edit(v: &serde_json::Value, key: &str, build: impl FnOnce(Vec<usize>) -> Edit) -> Result<serde_json::Value, String> {
    let id = v_docid(v)?;
    let arg = v.get(key).ok_or(format!("missing '{key}'"))?;
    let pages = parse_pages(key, arg)?;
    do_apply(id, build(pages))
}

fn parse_pages(key: &str, v: &serde_json::Value) -> Result<Vec<usize>, String> {
    if let Some(arr) = v.as_array() {
        return arr
            .iter()
            .map(|x| x.as_u64().map(|n| n as usize).ok_or(format!("{key}: bad page index")))
            .collect();
    }
    if let Some(n) = v.as_u64() {
        return Ok(vec![n as usize]);
    }
    Err(format!("{key}: bad page list"))
}

fn simple_session(v: &serde_json::Value, f: impl FnOnce(&mut Session, DocId) -> Result<serde_json::Value, String>) -> Result<serde_json::Value, String> {
    let id = v_docid(v)?;
    with(|s| f(s, id))
}

fn save_doc(v: &serde_json::Value) -> Result<serde_json::Value, String> {
    let id = v_docid(v)?;
    let path = v.get("path").and_then(|p| p.as_str()).ok_or("missing 'path'")?;
    with(|s| {
        let bytes = s.save_bytes(id).map_err(|e| e.to_string())?;
        std::fs::write(path, &*bytes).map_err(|e| format!("writing '{path}' failed ({e})"))?;
        Ok(serde_json::json!({ "bytes": bytes.len() }))
    })
}
