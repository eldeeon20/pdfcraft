// Flujo "crear": arma el PDF base, lo guarda y lo muestra para editarlo.
//
// main() -> Pantalla

import 'package:pdfcraft_flutter/api.dart';

Pantalla main() {
  return Pantalla('Crear un PDF', [
    Titulo('Crear un PDF'),
    Texto('Escribí el texto base. Después podés tocar la hoja para agregar texto o imágenes.'),
    Espacio(6),
    Columna([
      Entrada('titulo', 'Título del documento'),
      Espacio(4),
      Entrada('texto', 'Texto del documento', multilinea: true),
    ]),
    Espacio(12),
    Boton('Crear y guardar PDF', 'crear_guardar', icono: 'save'),
    Espacio(6),
    Boton('Crear y ver (sin guardar)', 'crear', primario: false),
    Espacio(4),
    Boton('Cancelar', 'al_inicio', primario: false),
  ]);
}

Future<Object?> Accion(String id) async {
  final s = yo();
  if (id == 'al_inicio') {
    return Vista('inicio');
  }
  if (id == 'crear' || id == 'crear_guardar') {
    final titulo = s.campo('titulo').trim();
    final texto = s.campo('texto');
    if (titulo.isEmpty) {
      aviso('falta el título');
      return null;
    }
    if (texto.trim().isEmpty) {
      aviso('falta el texto');
      return null;
    }
    final d = await crear(titulo, texto);
    s.fijarDoc(d);
    s.archivoFue('$titulo.pdf');
    s.fijarPagina(1);
    s.fijarCampo('modo', '');
    if (id == 'crear_guardar') {
      final ruta = await guardarComo();
      if (ruta != null) {
        aviso('creado y guardado en $ruta');
      } else {
        aviso('creado: $titulo (sin guardar)');
      }
    } else {
      aviso('creado: $titulo (${d.paginas} páginas)');
    }
    return Vista('ver');
  }
  return null;
}
