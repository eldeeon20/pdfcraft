/// Render del árbol de datos del script a widgets Flutter reales.
///
/// Los nodos vienen de `host/kit.dart` (creados por el script via el puente).
/// El diseño material lo tiene acá: tema oscuro limpio, cards, tipografía
/// generosa, scroll correcto y el visor de páginas nativo.
library;

import 'dart:typed_data';

import 'package:d4rt/d4rt.dart' as d4;
import 'package:flutter/material.dart';

import '../api.dart';
import 'kit.dart';
import 'sesion.dart';

const kAnchoMaximo = 560.0;

/// Nombres de icono para el menú de la AppBar.
IconData iconoDe(String nombre) {
  switch (nombre) {
    case 'edit':
      return Icons.edit_outlined;
    case 'save':
      return Icons.save_outlined;
    case 'trash':
      return Icons.delete_outline_rounded;
    case 'rotate':
      return Icons.rotate_right_rounded;
    case 'rotate_left':
      return Icons.rotate_left_rounded;
    case 'copy':
      return Icons.copy_rounded;
    case 'add_page':
      return Icons.post_add_rounded;
    case 'share':
      return Icons.ios_share_rounded;
    case 'creado':
      return Icons.person_add_rounded;
    case 'image':
      return Icons.image_outlined;
    default:
      return Icons.build_outlined;
  }
}

/// Convierte un nodo (o lista de nodos, o null) en widgets.
List<Widget> renderLista(Object? fuente) {
  final s = Sesion.i;
  final fuenteFinal = fuente == null
      ? const <Object?>[]
      : fuente is List
          ? fuente
          : <Object?>[fuente];
  return [for (final n in fuenteFinal.cast<Object?>()) _nodo(n, s)].nonNulls.toList();
}

Widget? _nodo(Object? n, Sesion s) {
  if (n == null) return null;
  if (n is d4.BridgedInstance) return _nodo(n.nativeObject, s);
  // Secciones de líneas de texto crudo (listas de párrafo, etc.).
  switch (n) {
    case Pantalla p:
      return _nodo(p.cuerpo, s); // la pantalla la maneja el host
    case Visor _:
      return const VisorPdf();
    case Lienzo _:
      return const LienzoPdf();
    case Titulo v:
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Text(v.texto, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      );
    case Texto v:
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(v.texto, style: const TextStyle(fontSize: 16, height: 1.45)),
      );
    case Boton v:
      final b = FilledButton(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        onPressed: () => AccionFlujo.i.presionar(v.id),
        child: Text(v.etiqueta),
      );
      return SizedBox(child: b, width: v.primario ? double.infinity : null);
    case Entrada v:
      return _CampoTexto(id: v.id, hint: v.hint, multilinea: v.multilinea, inicial: s.campo(v.id));
    case Panel v:
      final hijos = renderLista(v.opciones);
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: hijos),
        ),
      );
    case Fila v:
      final hijos = renderLista(v.opciones);
      return Row(
        children: [
          for (final h in hijos) Expanded(child: h),
        ],
      );
    case Columna v:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: renderLista(v.opciones),
      );
    case Espacio v:
      return SizedBox(height: v.tam);
    default:
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(n.toString(), style: const TextStyle(fontSize: 15)),
      );
  }
}

/// Un campo editable que guarda su valor en la Sesion.
class _CampoTexto extends StatefulWidget {
  _CampoTexto({required this.id, required this.hint, required this.multilinea, required this.inicial});
  final String id;
  final String hint;
  final bool multilinea;
  final String inicial;

  @override
  State<_CampoTexto> createState() => _CampoTextoState();
}

class _CampoTextoState extends State<_CampoTexto> {
  late final TextEditingController _c = TextEditingController(text: widget.inicial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _c,
        maxLines: widget.multilinea ? 8 : 1,
        keyboardType: widget.multilinea ? TextInputType.multiline : TextInputType.text,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
          labelText: widget.hint,
        ),
        onChanged: (t) => Sesion.i.fijarCampo(widget.id, t),
      ),
    );
  }
}

/// El visor: scroll vertical entre páginas + zoom por pinch, con la página
/// actual del núcleo. Se alimenta solo de la Sesion (doc, pagina, dpi).
class VisorPdf extends StatefulWidget {
  const VisorPdf({super.key});

  @override
  State<VisorPdf> createState() => _VisorPdfState();
}

class _VisorPdfState extends State<VisorPdf> {
  Uint8List? _pngActual;
  String _firma = '';
  String _error = '';

  Uint8List? _renderActual(Sesion s) {
    final d = s.docActual;
    if (d == null) return null;
    final firma = '${d.id}:${s.paginaActual}:${s.dpiActual}:${s.revision}';
    if (firma == _firma && _pngActual != null) return _pngActual;
    try {
      final png = d.png(s.paginaActual, s.dpiActual);
      _pngActual = png;
      _firma = firma;
      _error = '';
      return png;
    } catch (e) {
      _error = '$e';
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Sesion.i;
    final d = s.docActual;
    if (d == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No hay documento abierto', textAlign: TextAlign.center),
      );
    }
    _renderActual(s);
    final total = d.paginas < 1 ? 1 : d.paginas;
    return Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            maxScale: 5.0,
            minScale: 0.5,
            panEnabled: true,
            child: Center(
              child: _pngActual == null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error.isEmpty ? 'Renderizando…' : _error, textAlign: TextAlign.center),
                    )
                  : Image.memory(_pngActual!, fit: BoxFit.contain),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: s.paginaActual > 1 ? () => _cambiar(s, s.paginaActual - 1) : null,
              ),
              Expanded(
                child: Slider(
                  value: s.paginaActual.toDouble(),
                  min: 1,
                  max: total.toDouble(),
                  divisions: total > 1 ? total - 1 : 1,
                  label: '${s.paginaActual}',
                  onChanged: (v) => _cambiar(s, v.round()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: s.paginaActual < total ? () => _cambiar(s, s.paginaActual + 1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Va a otra página: la ordena Sesion y recarga el render en su frame.
  void _cambiar(Sesion s, int n) {
    s.fijarPagina(n);
    _firma = '';
    setState(() {});
  }
}

/// Una sola hoja tappable: preview fiel de la página actual y reporte del
/// toque normalizado para que el script coloque texto/imágenes.
class LienzoPdf extends StatefulWidget {
  const LienzoPdf({super.key});

  @override
  State<LienzoPdf> createState() => _LienzoPdfState();
}

class _LienzoPdfState extends State<LienzoPdf> {
  Uint8List? _png;
  String _firma = '';
  String _error = '';

  Uint8List? _render(Sesion s) {
    final d = s.docActual;
    if (d == null) return null;
    final firma = '${d.id}:${s.paginaActual}:${s.dpiActual}:${s.revision}';
    if (firma == _firma && _png != null) return _png;
    try {
      _png = d.png(s.paginaActual, s.dpiActual);
      _firma = firma;
      _error = '';
      return _png;
    } catch (e) {
      _error = '$e';
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Sesion.i;
    final d = s.docActual;
    if (d == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No hay documento abierto', textAlign: TextAlign.center),
      );
    }
    final png = _render(s);
    final tam = d.tamano(s.paginaActual);
    final aspecto = (tam.length == 2 && tam[1] > 0) ? tam[0] / tam[1] : 0.7727;
    final modo = s.campo('modo');
    return Column(
      children: [
        AspectRatio(
          aspectRatio: aspecto,
          child: LayoutBuilder(
            builder: (contexto, c) {
              return GestureDetector(
                onTapUp: (det) {
                  final ancho = c.maxWidth <= 0 ? 1.0 : c.maxWidth;
                  final alto = c.maxHeight <= 0 ? 1.0 : c.maxHeight;
                  final nx = (det.localPosition.dx / ancho).clamp(0.0, 1.0);
                  final ny = (det.localPosition.dy / alto).clamp(0.0, 1.0);
                  AccionFlujo.i.presionar(
                      'lienzo:$modo:${nx.toStringAsFixed(5)}:${ny.toStringAsFixed(5)}');
                },
                child: png == null
                    ? Container(
                        color: Colors.white,
                        alignment: Alignment.center,
                        child: Text(
                          _error.isEmpty ? 'Renderizando…' : _error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      )
                    : Image.memory(png, fit: BoxFit.fill, gaplessPlayback: true),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: s.paginaActual > 1
                    ? () {
                        s.fijarPagina(s.paginaActual - 1);
                        setState(() {});
                      }
                    : null,
              ),
              Expanded(
                child: Text(
                  'Página ${s.paginaActual} de ${d.paginas}',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: s.paginaActual < d.paginas
                    ? () {
                        s.fijarPagina(s.paginaActual + 1);
                        setState(() {});
                      }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Punto de contacto para las acciones de Boton.
class AccionFlujo {
  static final AccionFlujo i = AccionFlujo();
  void Function(String id)? _receptor;

  void conectar(void Function(String id) receptor) => _receptor = receptor;

  void presionar(String id) {
    final r = _receptor;
    if (r != null) r(id);
  }
}
