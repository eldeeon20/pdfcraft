// Flujo "editar": operar sobre la página actual del doc
// (rotar, borrar, duplicar, insertar hoja, guardar).
//
// main() -> Pantalla

import 'package:pdfcraft_flutter/api.dart';

Pantalla main() {
  final s = yo();
  final d = s.doc;
  if (d == null) {
    return Pantalla('Editar', [
      Titulo('Editar'),
      Texto('No hay documento abierto.'),
      Espacio(10),
      Boton('Ir al inicio', 'al_inicio'),
    ]);
  }
  return Pantalla('Editar', [
    Titulo('Editar'),
    Texto('Archivo: ${s.archivo}'),
    Texto('Trabajando la página ${s.pagina} de ${d.paginas}.'),
    Espacio(12),
    Panel([
      Titulo('Sobre la página ${s.pagina}'),
      Columna([
        Boton('Rotar 90° a la derecha', 'rotar', icono: 'rotate'),
        Espacio(4),
        Boton('Rotar 90° a la izquierda', 'rotar_izq'),
        Espacio(4),
        Boton('Duplicar', 'duplicar', icono: 'copy'),
        Espacio(4),
        Boton('Borrar', 'borrar', icono: 'trash'),
        Espacio(4),
        Boton('Insertar hoja nueva detrás', 'hoja', icono: 'add_page'),
      ]),
    ]),
    Espacio(10),
    Boton('Guardar como…', 'guardar', icono: 'save'),
    Espacio(4),
    Boton('Volver al visor', 'al_ver', primario: false),
  ]);
}

Future<Object?> Accion(String id) async {
  final s = yo();
  final d = s.doc;
  if (id == 'al_inicio') {
    return Vista('inicio');
  }
  if (id == 'al_ver') {
    return Vista('ver');
  }
  if (d == null) {
    aviso('no hay documento');
    return null;
  }
  switch (id) {
    case 'rotar':
      await d.rotar(s.pagina, 90);
      aviso('página ${s.pagina} rotada 90°');
      return null;
    case 'rotar_izq':
      await d.rotar(s.pagina, -90);
      aviso('página ${s.pagina} rotada -90°');
      return null;
    case 'borrar':
      if (d.paginas <= 1) {
        aviso('no puede quedar vacío');
        return null;
      }
      final p = s.pagina;
      await d.borrar(p);
      final quedan = d.paginas;
      s.fijarPagina(p > quedan ? quedan : p);
      aviso('página $p borrada; quedan $quedan');
      return Vista('editar');
    case 'duplicar':
      final p = s.pagina;
      await d.duplicar(p);
      s.fijarPagina(p + 1);
      aviso('duplicada la página $p');
      return Vista('editar');
    case 'hoja':
      final siguiente = s.pagina + 1;
      await d.hojaNueva(siguiente, 612, 792);
      s.fijarPagina(siguiente);
      aviso('hoja nueva insertada');
      return Vista('editar');
    case 'guardar':
      final ruta = await guardarComo();
      if (ruta != null) {
        aviso('guardado en $ruta');
      }
      return null;
  }
  return null;
}
