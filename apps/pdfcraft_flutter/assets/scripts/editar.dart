// Flujo "editar": editor de lienzo. La hoja blanca la rinde el host
// (EditorPdf); el script solo arma la pantalla y el menú.
//
// main() -> Pantalla   (caja: false = editor full-bleed)

import 'package:pdfcraft_flutter/api.dart';

Pantalla main() {
  final s = yo();
  final d = s.doc;
  if (d == null) {
    return Pantalla('Editor', [
      Texto('No hay documento abierto.'),
      Espacio(12),
      Boton('Ir al inicio', 'al_inicio'),
    ]);
  }
  return Pantalla(
    d.titulo,
    Editor(),
    caja: false,
    menu: [
      Boton('Ver', 'ver', icono: 'preview'),
      Boton('Cerrar documento', 'cerrar', icono: 'trash'),
    ],
  );
}

Future<Object?> Accion(String id) async {
  final s = yo();
  final d = s.doc;
  if (id == 'al_inicio') return Vista('inicio');
  if (id == 'ver') return Vista('ver');
  if (d == null) {
    aviso('no hay documento');
    return null;
  }
  if (id == 'guardar') {
    final ruta = await guardarComo();
    if (ruta != null) aviso('guardado');
    return null;
  }
  if (id == 'cerrar') {
    d.cerrar();
    s.fijarDoc(null);
    return Vista('inicio');
  }
  return null;
}
