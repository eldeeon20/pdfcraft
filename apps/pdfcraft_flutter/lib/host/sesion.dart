/// Estado de la app que el script ve (y el host rinde).
///
/// Es un objeto mutable singleton: el script lee `yo().doc`,
/// `yo().pagina`, muta con setters, y guarda valores de campos.
/// No toca dart:ffi: el acceso al core pasa por PdfDoc (api.dart).
library;

import '../api.dart';

/// Estado: doc actual, página, dpi, campos y mensajes, en un singleton.
class Sesion {
  static final Sesion i = Sesion();

  PdfDoc? docActual;
  int paginaActual = 1;
  double dpiActual = 144;
  String mensajeActual = '';
  String nombreArchivo = '';
  final Map<String, String> campos = {};

  bool get hay_doc => docActual != null;

  void fijarDoc(PdfDoc? d) {
    docActual = d;
    paginaActual = 1;
  }

  void fijarPagina(int n) {
    final paginas = docActual?.paginas ?? 1;
    paginaActual = n < 1 ? 1 : (n > paginas ? paginas : n);
  }

  void fijarDpi(double d) => dpiActual = d <= 40 ? 40 : d;

  void aviso(String m) => mensajeActual = m;

  String campo(String id) => campos[id] ?? '';

  void fijarCampo(String id, String valor) => campos[id] = valor;

  void archivoFue(String nombre) => nombreArchivo = nombre;
}

/// El script empieza SIEMPRE por acá.
Sesion yo() => Sesion.i;
