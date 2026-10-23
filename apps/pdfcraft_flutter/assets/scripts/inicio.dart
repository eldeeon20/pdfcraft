// Flujo "inicio": pantalla de bienvenida de PdfCraft.
//
// main() -> Pantalla

import 'package:pdfcraft_flutter/api.dart';

Pantalla main() {
  final d = yo().doc;
  final sub = d == null
      ? 'Nada abierto todavía. ¿Qué querés hacer?'
      : 'Abierto: ${d.titulo} (${d.paginas} páginas).';

  return Pantalla('PdfCraft', [
    Titulo('PdfCraft'),
    Texto(sub),
    Espacio(14),
    Columna([
      Boton('Abrir un PDF', 'abrir'),
      Espacio(10),
      Boton('Crear uno nuevo', 'crear'),
      Espacio(10),
      Boton('Seguir en el visor', 'ver', primario: false),
    ]),
    Espacio(18),
    Texto('core v${versionCore()} — gui por script d4rt'),
  ]);
}

// Acciones de la home.
Future<Object?> Accion(String id) async {
  if (id == 'abrir') {
    final d = await abrir();
    if (d != null) {
      return Vista('ver');
    }
    return null; // cancelado
  }
  if (id == 'crear') {
    return Vista('crear');
  }
  if (id == 'ver') {
    if (yo().doc == null) {
      aviso('primero abrí un PDF');
      return null;
    }
    return Vista('ver');
  }
  return null;
}
