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

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'host/ffi.dart';
import 'host/sesion.dart';

export 'host/kit.dart' show Pantalla, Visor, Lienzo, Vista, Texto, Titulo, Boton, Entrada, Fila, Columna, Panel, Espacio;
export 'host/sesion.dart' show Sesion, yo;

/// Un documento abierto en el core (una vez, hasta cerrarlo).
class PdfDoc {
  PdfDoc._(this.id, this.titulo, this.paginas, [List<List<double>> tamanos = const []])
      : _tamanos = tamanos;

  final int id;
  String titulo;
  int paginas;
  List<List<double>> _tamanos;

  /// Abre un PDF del disco (ruta ya con permiso del picker).
  static Future<PdfDoc> abrir(String ruta) async {
    final nombre = ruta.contains('/') ? ruta.split('/').last : ruta;
    final r = Core.i.request({
      'm': 'open',
      'path': ruta,
    });
    final id = r['doc'] as int;
    return PdfDoc._(
      id,
      (r['title'] as String?) ?? nombre,
      (r['pages'] as num?)?.toInt() ?? 1,
      Core.i.tamanos(id),
    );
  }

  /// Crea un PDF de texto (una página por ~40 líneas, tamaño Letter).
  static Future<PdfDoc> crear(String titulo, String texto) async {
    final r = Core.i.request({
      'm': 'create',
      'title': titulo,
      'text': texto,
    });
    final id = r['doc'] as int;
    return PdfDoc._(
      id,
      titulo,
      (r['pages'] as num?)?.toInt() ?? 1,
      Core.i.tamanos(id),
    );
  }

  /// Tamaño [ancho, alto] de [pagina] (1 = primera) en puntos de display.
  List<double> tamano(int pagina) {
    final i = pagina - 1;
    if (i >= 0 && i < _tamanos.length) return _tamanos[i];
    return const <double>[612, 792];
  }

  /// Ancho de [pagina] en puntos de display.
  double anchoPagina(int pagina) => tamano(pagina)[0];

  /// Alto de [pagina] en puntos de display.
  double altoPagina(int pagina) => tamano(pagina)[1];

  /// Cuántos textos/imágenes editables hay agregados en [pagina].
  int cantidadContenido(int pagina) => Core.i.contenido(id, pagina).length;

  /// Agrega texto en [x],[y] (display space, origen abajo-izquierda; [y] es
  /// el borde superior de la primera línea).
  Future<void> agregarTexto(
    int pagina,
    double x,
    double y,
    String texto, {
    double ancho = 0,
    double tam = 14,
    bool negrita = false,
    bool italica = false,
    String alineacion = 'left',
    String familia = 'helvetica',
  }) async {
    final t = tamano(pagina);
    final double w = ancho > 0 ? ancho : (t[0] - x - 24).clamp(40.0, t[0]).toDouble();
    final rect = [x, y - tam * 1.2, x + w, y];
    Core.i.agregarTexto(id, pagina, rect, texto,
        tam: tam, negrita: negrita, italica: italica, alineacion: alineacion, familia: familia);
    Sesion.i.revision++;
  }

  /// Agrega una imagen desde [ruta] centrada en [x],[y] (display space).
  Future<void> agregarImagen(
    int pagina,
    String ruta,
    double x,
    double y, {
    double ancho = 180,
    double alto = 180,
  }) async {
    final t = tamano(pagina);
    double w = ancho.clamp(24.0, t[0]).toDouble();
    double h = alto.clamp(24.0, t[1]).toDouble();
    try {
      final nat = _dimensionesImagen(await File(ruta).readAsBytes());
      if (nat != null && nat[0] > 0 && nat[1] > 0) {
        final k = math.min(w / nat[0], h / nat[1]);
        w = nat[0] * k;
        h = nat[1] * k;
      }
    } catch (_) {}
    final double cx = x.clamp(w / 2, t[0] - w / 2).toDouble();
    final double cy = y.clamp(h / 2, t[1] - h / 2).toDouble();
    final rect = [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2];
    Core.i.agregarImagen(id, pagina, ruta, rect: rect);
    Sesion.i.revision++;
  }

  /// Borra el último elemento agregado en [pagina].
  Future<void> borrarUltimo(int pagina) async {
    final n = cantidadContenido(pagina);
    if (n == 0) return;
    Core.i.borrarContenido(id, pagina, n - 1);
    Sesion.i.revision++;
  }

  /// Borra el elemento [index] agregado en [pagina].
  Future<void> borrarContenido(int pagina, int index) async {
    Core.i.borrarContenido(id, pagina, index);
    Sesion.i.revision++;
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
    Sesion.i.revision++;
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
    _tamanos = Core.i.tamanos(id);
    Sesion.i.revision++;
  }
}

/// Dimensiones [ancho, alto] de un PNG/JPEG, o null si no se reconocen.
List<double>? _dimensionesImagen(Uint8List b) {
  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    final w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
    final h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
    if (w > 0 && h > 0) return [w.toDouble(), h.toDouble()];
  }
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final len = (b[i + 2] << 8) | b[i + 3];
      if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
        final h = (b[i + 5] << 8) | b[i + 6];
        final w = (b[i + 7] << 8) | b[i + 8];
        if (w > 0 && h > 0) return [w.toDouble(), h.toDouble()];
      }
      if (len < 2) break;
      i += 2 + len;
    }
  }
  return null;
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
