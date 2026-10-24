// Flujo "inicio": abrir un PDF o empezar con una hoja en blanco.
//
// main() -> Pantalla

import 'package:pdfcraft_flutter/api.dart';

Pantalla main() {
  final d = yo().doc;
  final cuerpo = [];

  if (d == null) {
    cuerpo.add(Texto('Abrí un PDF o creá una hoja en blanco para escribir.'));
    cuerpo.add(Espacio(20));
    cuerpo.add(Boton('Abrir PDF', 'abrir', icono: 'open'));
    cuerpo.add(Espacio(10));
    cuerpo.add(Boton('Nuevo PDF en blanco', 'nuevo', primario: false, icono: 'add_page'));
  } else {
    cuerpo.add(Texto('${d.titulo} · ${d.paginas} páginas'));
    cuerpo.add(Espacio(18));
    cuerpo.add(Boton('Abrir el editor', 'editar', icono: 'edit'));
    cuerpo.add(Espacio(10));
    cuerpo.add(Boton('Ver', 'ver', primario: false, icono: 'preview'));
    cuerpo.add(Espacio(10));
    cuerpo.add(Boton('Nuevo PDF en blanco', 'nuevo', primario: false, icono: 'add_page'));
  }

  return Pantalla('PdfCraft', cuerpo);
}

Future<Object?> Accion(String id) async {
  final s = yo();
  if (id == 'abrir') {
    final d = await abrir();
    if (d != null) return Vista('editar');
    return null;
  }
  if (id == 'nuevo') {
    final d = await crear('Documento', '');
    s.fijarDoc(d);
    s.archivoFue('Documento.pdf');
    s.fijarPagina(1);
    s.fijarCampo('modo', '');
    aviso('hoja en blanco creada');
    return Vista('editar');
  }
  if (id == 'editar') {
    if (s.doc == null) {
      aviso('primero abrí o creá un PDF');
      return null;
    }
    return Vista('editar');
  }
  if (id == 'ver') {
    if (s.doc == null) return null;
    return Vista('ver');
  }
  return null;
}
