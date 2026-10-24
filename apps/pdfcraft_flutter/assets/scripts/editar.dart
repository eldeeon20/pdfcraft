// Flujo "editar": editor real de contenido. Muestra la hoja actual y deja
// tocar para colocar texto o una imagen; también opera sobre páginas.
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

  final modo = s.campo('modo');
  final imagen = s.campo('imagen');
  final agregados = d.cantidadContenido(s.pagina);

  final cuerpo = [];
  cuerpo.add(Titulo('Editar contenido'));
  cuerpo.add(Texto('Tocá la hoja para colocar el texto o la imagen.'));
  cuerpo.add(Texto('Página ${s.pagina} de ${d.paginas} · elementos agregados: $agregados'));
  cuerpo.add(Lienzo());
  cuerpo.add(Espacio(10));
  cuerpo.add(Entrada('texto', 'Texto a agregar en la hoja', multilinea: true));
  cuerpo.add(Espacio(6));
  cuerpo.add(Fila([
    Boton(modo == 'texto' ? 'Colocando texto…' : 'Colocar texto', 'modo_texto', icono: 'edit'),
    Boton(modo == 'imagen' ? 'Colocando imagen…' : 'Colocar imagen', 'modo_imagen', icono: 'image'),
  ]));
  cuerpo.add(Espacio(6));
  cuerpo.add(Boton(
    imagen.isEmpty ? 'Elegir imagen…' : 'Imagen: ${imagen.split('/').last}',
    'elegir_imagen',
    primario: false,
    icono: 'image',
  ));
  if (agregados > 0) {
    cuerpo.add(Espacio(6));
    cuerpo.add(Boton('Borrar último agregado', 'borrar_ultimo', primario: false, icono: 'trash'));
  }
  cuerpo.add(Espacio(14));
  cuerpo.add(Panel([
    Titulo('Página ${s.pagina}'),
    Columna([
      Boton('Rotar 90° a la derecha', 'rotar', icono: 'rotate'),
      Espacio(4),
      Boton('Rotar 90° a la izquierda', 'rotar_izq'),
      Espacio(4),
      Boton('Duplicar', 'duplicar', icono: 'copy'),
      Espacio(4),
      Boton('Borrar página', 'borrar', icono: 'trash'),
      Espacio(4),
      Boton('Insertar hoja nueva detrás', 'hoja', icono: 'add_page'),
    ]),
  ]));
  cuerpo.add(Espacio(12));
  cuerpo.add(Boton('Guardar PDF', 'guardar', icono: 'save'));
  cuerpo.add(Espacio(4));
  cuerpo.add(Boton('Volver al visor', 'al_ver', primario: false));

  return Pantalla('Editar', cuerpo);
}

Future<Object?> Accion(String id) async {
  final s = yo();
  final d = s.doc;
  if (id == 'al_inicio') return Vista('inicio');
  if (id == 'al_ver') return Vista('ver');
  if (d == null) {
    aviso('no hay documento');
    return null;
  }

  if (id == 'modo_texto') {
    s.fijarCampo('modo', 'texto');
    aviso('tocá la hoja donde querés el texto');
    return Vista('editar');
  }
  if (id == 'modo_imagen') {
    if (s.campo('imagen').isEmpty) {
      aviso('primero elegí una imagen');
      return null;
    }
    s.fijarCampo('modo', 'imagen');
    aviso('tocá la hoja donde querés la imagen');
    return Vista('editar');
  }
  if (id == 'elegir_imagen') {
    final ruta = await elegirImagen();
    if (ruta != null) {
      s.fijarCampo('imagen', ruta);
    }
    return Vista('editar');
  }
  if (id == 'borrar_ultimo') {
    await d.borrarUltimo(s.pagina);
    s.fijarCampo('modo', '');
    aviso('elemento borrado');
    return Vista('editar');
  }

  if (id.startsWith('lienzo:')) {
    final partes = id.split(':');
    if (partes.length < 4) return null;
    final modo = partes[1];
    final nx = double.tryParse(partes[2]) ?? 0.5;
    final ny = double.tryParse(partes[3]) ?? 0.5;
    final ancho = d.anchoPagina(s.pagina);
    final alto = d.altoPagina(s.pagina);
    final x = nx * ancho;
    final y = (1 - ny) * alto;
    if (modo == 'texto') {
      final texto = s.campo('texto').trim();
      if (texto.isEmpty) {
        aviso('escribí el texto abajo antes de tocar la hoja');
        return null;
      }
      await d.agregarTexto(s.pagina, x, y, texto);
      s.fijarCampo('modo', '');
      aviso('texto agregado en la página ${s.pagina}');
      return Vista('editar');
    }
    if (modo == 'imagen') {
      final ruta = s.campo('imagen');
      if (ruta.isEmpty) {
        aviso('elegí una imagen primero');
        return null;
      }
      await d.agregarImagen(s.pagina, ruta, x, y);
      s.fijarCampo('modo', '');
      aviso('imagen agregada en la página ${s.pagina}');
      return Vista('editar');
    }
    aviso('elegí "Colocar texto" o "Colocar imagen" y después tocá la hoja');
    return null;
  }

  switch (id) {
    case 'rotar':
      await d.rotar(s.pagina, 90);
      aviso('página ${s.pagina} rotada 90°');
      return Vista('editar');
    case 'rotar_izq':
      await d.rotar(s.pagina, -90);
      aviso('página ${s.pagina} rotada -90°');
      return Vista('editar');
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
      final nueva = s.pagina + 1;
      await d.hojaNueva(s.pagina, 612, 792);
      s.fijarPagina(nueva);
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
