// Flujo "ver": el visor. La imagen, el zoom y el scroll los renderiza el
// host (VisorPdf); el script arma la pantalla y define el menú.
//
// main() -> Pantalla   (caja: false = visor full-bleed)

import 'package:pdfcraft_flutter/api.dart';

Pantalla main() {
  final s = yo();
  final d = s.doc;
  if (d == null) {
    return Pantalla('Sin documento', [
      Texto('No hay nada abierto.'),
      Espacio(12),
      Boton('Ir al inicio', 'al_inicio'),
    ]);
  }
  return Pantalla(
    d.titulo,
    Visor(),
    caja: false,
    menu: [
      Boton('Editar', 'ir_editar', icono: 'edit'),
      Boton('Guardar PDF', 'guardar', icono: 'save'),
      Boton('Nuevo PDF', 'nuevo', icono: 'add_page'),
      Boton('Cerrar documento', 'cerrar', icono: 'trash'),
    ],
  );
}

Future<Object?> Accion(String id) async {
  final s = yo();
  switch (id) {
    case 'ir_editar':
      return Vista('editar');
    case 'guardar':
      final ruta = await guardarComo();
      if (ruta != null) aviso('guardado');
      return null;
    case 'nuevo':
      final d = await crear('Documento', '');
      s.fijarDoc(d);
      s.archivoFue('Documento.pdf');
      s.fijarPagina(1);
      s.fijarCampo('modo', '');
      return Vista('editar');
    case 'cerrar':
      s.doc?.cerrar();
      s.fijarDoc(null);
      aviso('documento cerrado');
      return Vista('inicio');
    case 'al_inicio':
      return Vista('inicio');
  }
  return null;
}
