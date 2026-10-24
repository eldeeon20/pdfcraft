/// Nodos de interfaz que el script arma; el host los convierte en widgets
/// Flutter reales. Son datos puros (sin Flutter): el toque final lo tiene
/// `render.dart`. Menos es más: cada clase hace una sola cosa.
library;

class Titulo {
  Titulo(this.texto);
  final String texto;
}

class Texto {
  Texto(this.texto);
  final String texto;
}

class Boton {
  Boton(this.etiqueta, this.id, {this.primario = true, this.icono = ''});
  final String etiqueta;
  final String id;
  final bool primario;
  /// Nombre corto para el menú de la AppBar: 'edit', 'save', 'trash', …
  final String icono;
}

class Entrada {
  Entrada(this.id, this.hint, {this.multilinea = false});
  /// Id con el que el script pregunta el valor (`yo().campo(id)`).
  final String id;
  final String hint;
  final bool multilinea;
}

class Fila {
  Fila(this.opciones, {this.reparto = false});
  final List<Object?> opciones;
  /// `true`: los hijos se reparten el ancho igual.
  final bool reparto;
}

class Columna {
  Columna(this.opciones);
  final List<Object?> opciones;
}

class Panel {
  Panel(this.opciones);
  final List<Object?> opciones;
}

class Espacio {
  Espacio([this.tam = 16.0]);
  final double tam;
}

/// El visor: el host lo construye (scroll, zoom, páginas). El script solo
/// lo pide con el modo actual ya puesto en la Sesion.
class Visor {
  Visor();
}

/// Una hoja tappable: muestra la página actual y reporta el toque como
/// `lienzo:<modo>:<x>:<y>` (x,y normalizados 0..1, origen arriba-izquierda).
class Lienzo {
  Lienzo();
}

/// Editor de lienzo full-bleed: hoja blanca, escribir tocando, elegir imagen,
/// arrastrar textos/imágenes y guardar. El host lo construye entero.
class Editor {
  Editor();
}

/// Una pantalla completa del script.
class Pantalla {
  Pantalla(this.titulo, this.cuerpo, {this.caja = true, this.menu = const []});
  final String titulo;
  final Object? cuerpo;
  /// `false`: sin panel sólido detrás (para el visor full-bleed).
  final bool caja;
  /// Botones del menú (AppBar).
  final List<Object?> menu;
}

/// EL script pide cambiar a otro flujo (`Vista('ver')`).
class Vista {
  Vista(this.id);
  final String id;
}
