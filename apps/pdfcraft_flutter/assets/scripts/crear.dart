// Flujo "crear": PDF de texto. El usuario escribe y el core lo arma
// (una página por ~40 líneas, tamaño Letter).
//
// main() -> Pantalla

import 'package:pdfcraft_flutter/api.dart';

Pantalla main() {
  return Pantalla('Crear un PDF', [
    Titulo('Crear un PDF'),
    Texto('Escribí el texto; cada página nueva se llena sola.'),
    Espacio(6),
    Columna([
      Entrada('titulo', 'Título del documento'),
      Espacio(4),
      Entrada('texto', 'Texto del documento', multilinea: true),
    ]),
    Espacio(12),
    Boton('Crear el PDF', 'crear'),
    Espacio(8),
    Boton('Cancelar', 'al_inicio', primario: false),
  ]);
}

Future<Object?> Accion(String id) async {
  final s = yo();
  if (id == 'al_inicio') {
    return Vista('inicio');
  }
  if (id == 'crear') {
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
    aviso('creado: $titulo (${d.paginas} páginas)');
    return Vista('ver');
  }
  return null;
}
