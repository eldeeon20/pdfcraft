/// Puente Dart al core PdfCraft por FFI: `libpdfcraft_ffi.so`.
///
/// Protocolo (ver `crates/pdfcraft-ffi/src/lib.rs`):
/// - `request(map)` → mapa JSON `{"ok": true, ...}` / `{"ok": false, "err": "..."}`.
/// - `paginaPng(doc, page, dpi)` → PNG crudo (o JSON `{"ok":false,...}` de error).
///
/// La memoria que el core devuelve se libera SIEMPRE con el propio
/// `pdfcraft_free` del .so (mismo allocator Rust); el malloc de dart:ffi solo
/// se usa para los buffers del anfitrión.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Excepción con el mensaje del core.
class CoreError implements Exception {
  CoreError(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

/// El puente al .so. Singleton perezoso: `Core.i`.
class Core {
  Core._();
  static final Core i = Core._();

  static const _nombre = 'libpdfcraft_ffi.so';

  bool cargado = false;
  int version = 0;

  /// Versión del protocolo del core; carga el .so si falta.
  int versionDelCore() {
    _asegurar();
    return version;
  }

  Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Uint32>)? _call;
  Pointer<Uint8> Function(int, int, double, Pointer<Uint32>)? _image;
  void Function(Pointer<Uint8>, int)? _libre;

  void _asegurar() {
    if (cargado) return;
    final lib = DynamicLibrary.open(_nombre);

    final ping = lib.lookupFunction<Int64 Function(), int Function()>('pdfcraft_ping');
    version = ping();

    _call = lib.lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>, Uint32, Pointer<Uint32>),
        Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Uint32>)>('pdfcraft_call');

    _image = lib.lookupFunction<
        Pointer<Uint8> Function(Uint64, Uint32, Double, Pointer<Uint32>),
        Pointer<Uint8> Function(int, int, double, Pointer<Uint32>)>('pdfcraft_image');

    _libre = lib.lookupFunction<Void Function(Pointer<Uint8>, Uint32),
        void Function(Pointer<Uint8>, int)>('pdfcraft_free');

    cargado = true;
  }

  /// Llamada JSON: devuelve el mapa de respuesta o lanza [CoreError].
  Map<String, dynamic> request(Map<String, dynamic> cuerpo) {
    _asegurar();
    final datos = utf8.encode(jsonEncode(cuerpo));
    final reqPtr = malloc<Uint8>(datos.length);
    final outLen = malloc<Uint32>();
    Pointer<Uint8> resp = nullptr;
    try {
      reqPtr.asTypedList(datos.length).setAll(0, datos);
      resp = _call!(reqPtr, datos.length, outLen);
      if (resp == nullptr) {
        throw CoreError('${cuerpo['m']}: el core no respondió');
      }
      final n = outLen.value;
      if (n == 0) {
        throw CoreError('${cuerpo['m']}: respuesta vacía');
      }
      final cadena = utf8.decode(resp.asTypedList(n));
      final mapa = jsonDecode(cadena) as Map<String, dynamic>;
      if (mapa['ok'] != true) {
        final err = mapa['err']?.toString() ?? 'error';
        throw CoreError('${cuerpo['m']}: $err');
      }
      return mapa;
    } finally {
      if (resp != nullptr) _libre!(resp, outLen.value);
      malloc.free(reqPtr);
      malloc.free(outLen);
    }
  }

  /// Tamaños de página en puntos de display: `[[w,h], ...]`.
  List<List<double>> tamanos(int doc) {
    final r = request({'m': 'sizes', 'doc': doc});
    final crudo = r['sizes'] as List? ?? const [];
    return [
      for (final e in crudo)
        [for (final v in (e as List)) (v as num).toDouble()],
    ];
  }

  /// Agrega texto editable en [rect] (display space, origen abajo-izquierda).
  void agregarTexto(
    int doc,
    int pagina,
    List<double> rect,
    String texto, {
    double tam = 14,
    bool negrita = false,
    bool italica = false,
    String alineacion = 'left',
    String familia = 'helvetica',
    List<double>? color,
  }) {
    request({
      'm': 'addtext',
      'doc': doc,
      'page': pagina,
      'rect': rect,
      'text': texto,
      'size': tam,
      'bold': negrita,
      'italic': italica,
      'align': alineacion,
      'family': familia,
      if (color != null) 'color': color,
    });
  }

  /// Agrega una imagen desde [ruta] (rect opcional en display space).
  void agregarImagen(int doc, int pagina, String ruta, {List<double>? rect}) {
    request({
      'm': 'addimage',
      'doc': doc,
      'page': pagina,
      'path': ruta,
      if (rect != null) 'rect': rect,
    });
  }

  /// Elementos editables agregados en [pagina].
  List<Map<String, dynamic>> contenido(int doc, int pagina) {
    final r = request({'m': 'added', 'doc': doc, 'page': pagina});
    final crudo = r['items'] as List? ?? const [];
    return [
      for (final e in crudo) Map<String, dynamic>.from(e as Map),
    ];
  }

  /// Borra el elemento [index] de [pagina].
  void borrarContenido(int doc, int pagina, int index) {
    request({'m': 'delcontent', 'doc': doc, 'page': pagina, 'index': index});
  }

  /// Renderiza una página a PNG (crudo) o lanza [CoreError].
  Uint8List paginaPng(int doc, int pagina, double dpi) {
    _asegurar();
    final outLen = malloc<Uint32>();
    Pointer<Uint8> png = nullptr;
    try {
      png = _image!(doc, pagina, dpi, outLen);
      if (png == nullptr) {
        throw CoreError('render puntual: el core no respondió');
      }
      final n = outLen.value;
      if (n == 0) {
        throw CoreError('render puntual: imagen vacía');
      }
      final bytes = png.asTypedList(n);
      if (n > 1 && bytes[0] == 0x7b) {
        // Llegó JSON de error en vez de imagen.
        String err = 'error';
        try {
          final mapa = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          err = mapa['err']?.toString() ?? 'error';
        } catch (_) {}
        throw CoreError('render: $err');
      }
      return Uint8List.fromList(bytes);
    } finally {
      if (png != nullptr) _libre!(png, outLen.value);
      malloc.free(outLen);
    }
  }
}
