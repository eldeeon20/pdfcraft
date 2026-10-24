/// Esta es la API **bridged** que el script ve con
/// `import 'package:pdfcraft_flutter/api.dart';`
///
/// Clases:
/// - `PdfDoc`: documento abierto del core (rotar, guardar, render…).
/// - `Sesion`+`yo()`: estado de la app (kit de vistas vía el host).
///
/// Funciones globales (sin import):
/// - `aviso(texto)`: deja un mensaje para el usuario.
/// - `versionCore()`: qué .so hay cargado.
///
/// El .so nunca se toca acá: todo pasa por `host/ffi.dart`.
library;

import 'dart:typed_data';

import 'host/ffi.dart';
import 'host/sesion.dart';

export 'host/kit.dart' show Pantalla, Visor, Vista, Texto, Titulo, Boton, Entrada, Fila, Columna, Panel, Espacio;
export 'host/sesion.dart' show Sesion, yo;

/// Un documento abierto en el core (una vez, hasta cerrarlo).
class PdfDoc {
  PdfDoc._(this.id, this.titulo, this.paginas);

  final int id;
  String titulo;
  int paginas;

  /// Abre un PDF del disco (ruta ya con permiso del picker).
  static Future<PdfDoc> abrir(String ruta) async {
    final nombre = ruta.contains('/') ? ruta.split('/').last : ruta;
    final r = Core.i.request({
      'm': 'open',
      'path': ruta,
    });
    return PdfDoc._(
      r['doc'] as int,
      (r['title'] as String?) ?? nombre,
      (r['pages'] as num?)?.toInt() ?? 1,
    );
  }

  /// Crea un PDF de texto (una página por ~40 líneas, tamaño Letter).
  static Future<PdfDoc> crear(String titulo, String texto) async {
    final r = Core.i.request({
      'm': 'create',
      'title': titulo,
      'text': texto,
    });
    return PdfDoc._(
      r['doc'] as int,
      titulo,
      (r['pages'] as num?)?.toInt() ?? 1,
    );
  }

  /// La página [pagina] (1 = primera) como PNG a los dpi del núcleo del doc.
  Uint8List png(int pagina, double dpi) => Core.i.paginaPng(id, pagina, dpi);

  /// El texto de [pagina], tal cual lo entrega el core.
  Future<String> textoDe(int pagina) async {
    final r = Core.i.request({'m': 'pages', 'doc': id});
    final total = (r['pages'] as num?)?.toInt() ?? 1;
    if (pagina < 1 || pagina > total) return '';
    final t = Core.i.request({'m': 'text', 'doc': id, 'page': pagina});
    return (t['text'] as String?) ?? '';
  }

  Future<void> rotar(int pagina, int grados) async {
    await Core.i.request({'m': 'rotate', 'doc': id, 'pages': pagina, 'deg': grados});
  }

  Future<void> atrasRotar(int pagina) => rotar(pagina, -90);

  Future<void> del(int pagina) async {
    await Core.i.request({'m': 'delete', 'doc': id, 'pages': pagina});
    _refrescar();
  }

  Future<void> mover(int desde, int hasta) async {
    await Core.i.request({'m': 'move', 'doc': id, 'pages': desde, 'to': hasta});
    _refrescar();
  }

  Future<void> duplicar(int pagina) async {
    await Core.i.request({'m': 'duplicate', 'doc': id, 'pages': pagina});
    _refrescar();
  }

  Future<void> hojaNueva(int despuesDe, double ancho, double alto) async {
    await Core.i.request({
      'm': 'blank',
      'doc': id,
      'at': despuesDe,
      'w': ancho,
      'h': alto,
    });
    _refrescar();
  }

  Future<void> guardar(String ruta) async {
    await Core.i.request({'m': 'save', 'doc': id, 'path': ruta});
  }

  void cerrar() {
    try {
      Core.i.request({'m': 'close', 'doc': id});
    } catch (_) {}
  }

  void _refrescar() {
    final r = Core.i.request({'m': 'pages', 'doc': id});
    paginas = (r['pages'] as num?)?.toInt() ?? paginas;
  }
}

/// El script deja un mensaje para el usuario (SnackBar).
void aviso(String texto) {
  Sesion.i.aviso(texto);
}

/// Qué .so está cargado (para pantalla "acerca").
String versionCore() {
  try {
    return Core.i.versionDelCore().toString();
  } catch (_) {
    return '?';
  }
}
