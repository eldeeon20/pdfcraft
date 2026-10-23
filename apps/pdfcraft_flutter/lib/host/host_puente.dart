/// Enlace del script con el host: elegir PDF (SAF) y guardarlo.
///
/// `HostPuente.abrir()` / `HostPuente.guardarComo()` son los puentes async
/// que el script consume; el widget de la app setea los hooks al arrancar.
library;

import '../api.dart';
import '../host/sesion.dart';

/// El host setea estos hooks una vez al arrancar.
class HostPuente {
  static Future<PdfDoc?> Function()? abrirHook;
  static Future<String?> Function()? guardarHook;

  static Future<PdfDoc?> abrir() async {
    final h = abrirHook;
    if (h == null) {
      Sesion.i.aviso('el host no dejó abrir archivos todavía');
      return null;
    }
    return h();
  }

  static Future<String?> guardarComo() async {
    final h = guardarHook;
    if (h == null) {
      Sesion.i.aviso('el host no dejó guardar todavía');
      return null;
    }
    return h();
  }
}
