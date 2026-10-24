/// Editor de lienzo: la hoja blanca ocupa la pantalla.
///
/// Herramientas: escribir tocando (diálogo), elegir imagen y tocar para
/// colocarla, arrastrar textos/imágenes para moverlos, deshacer/rehacer,
/// páginas y guardar. Todo el estado vive en `Sesion`/`PdfDoc`.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';
import 'host_puente.dart';
import 'sesion.dart';

class EditorPdf extends StatefulWidget {
  const EditorPdf({super.key});

  @override
  State<EditorPdf> createState() => _EditorPdfState();
}

class _EditorPdfState extends State<EditorPdf> {
  Uint8List? _png;
  String _firma = '';
  String _itemsFirma = '';
  String _error = '';
  List<Map<String, dynamic>> _items = const [];

  String _modo = '';
  String? _imagen;

  int? _dragIndex;
  List<double>? _dragOriginal;
  double _startX = 0;
  double _startY = 0;
  List<double>? _ghost;

  bool _ocupado = false;

  // ------------------------------------------------------------- render

  void _syncItems(Sesion s) {
    final d = s.docActual;
    if (d == null) return;
    final firma = '${d.id}:${s.paginaActual}:${s.revision}';
    if (firma == _itemsFirma) return;
    try {
      _items = d.contenido(s.paginaActual);
    } catch (e) {
      _items = const [];
      _error = '$e';
    }
    _itemsFirma = firma;
    _firma = '';
  }

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

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final s = Sesion.i;
    final d = s.docActual;
    if (d == null) {
      return const Center(child: Text('No hay documento abierto'));
    }
    _syncItems(s);
    final png = _render(s);
    final t = d.tamano(s.paginaActual);
    final aspecto = (t.length == 2 && t[1] > 0) ? t[0] / t[1] : 0.7727;

    return Column(
      children: [
        Expanded(
          child: Container(
            color: const Color(0xFFE9ECF3),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AspectRatio(
                  aspectRatio: aspecto,
                  child: LayoutBuilder(
                    builder: (contexto, c) {
                      final size = Size(c.maxWidth, c.maxHeight);
                      return GestureDetector(
                        onTapUp: (det) => _tap(det.localPosition, size),
                        onPanStart: (det) => _panStart(det.localPosition, size),
                        onPanUpdate: (det) => _panUpdate(det.localPosition, size),
                        onPanEnd: (_) => _panEnd(),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (png == null)
                                Center(
                                  child: Text(
                                    _error.isEmpty ? 'Renderizando…' : _error,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.black54),
                                  ),
                                )
                              else
                                Image.memory(png, fit: BoxFit.fill, gaplessPlayback: true),
                              if (_ghost != null) _ghostBox(size, t),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        _barra(s, d),
      ],
    );
  }

  Widget _ghostBox(Size size, List<double> t) {
    final r = _ghost!;
    final left = (r[0] / t[0]).clamp(0.0, 1.0).toDouble() * size.width;
    final top = (1 - r[3] / t[1]).clamp(0.0, 1.0).toDouble() * size.height;
    final w = ((r[2] - r[0]) / t[0]).clamp(0.0, 1.0).toDouble() * size.width;
    final h = ((r[3] - r[1]) / t[1]).clamp(0.0, 1.0).toDouble() * size.height;
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD8A94A), width: 2),
            color: const Color(0x22D8A94A),
          ),
        ),
      ),
    );
  }

  Widget _barra(Sesion s, PdfDoc d) {
    return SafeArea(
      top: false,
      child: Container(
        color: const Color(0xFF1A1C2A),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Página anterior',
                  onPressed: s.paginaActual > 1 ? () => _pagina(s, s.paginaActual - 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text(
                  'Página ${s.paginaActual} de ${d.paginas}',
                  style: const TextStyle(fontSize: 13),
                ),
                IconButton(
                  tooltip: 'Página siguiente',
                  onPressed: s.paginaActual < d.paginas ? () => _pagina(s, s.paginaActual + 1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Agregar hoja',
                  onPressed: _ocupado ? null : () => _hoja(d),
                  icon: const Icon(Icons.note_add_outlined),
                ),
                IconButton(
                  tooltip: 'Borrar último agregado',
                  onPressed: _ocupado ? null : () => _borrarUltimo(d),
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _herramienta(
                  Icons.text_fields_rounded,
                  'Texto',
                  _modo == 'texto',
                  () => setState(() => _modo = _modo == 'texto' ? '' : 'texto'),
                ),
                _herramienta(Icons.image_outlined, 'Imagen', _modo == 'imagen', _elegir),
                _herramienta(Icons.undo_rounded, 'Deshacer', false,
                    _ocupado ? null : () => _deshacer(d)),
                _herramienta(Icons.redo_rounded, 'Rehacer', false,
                    _ocupado ? null : () => _rehacer(d)),
                _herramienta(Icons.save_outlined, 'Guardar', false,
                    () => HostPuente.guardarComo()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _herramienta(IconData icono, String tip, bool activo, VoidCallback? onTap) {
    return IconButton(
      tooltip: tip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        foregroundColor: activo ? const Color(0xFFE3B872) : const Color(0xFFD5DAE6),
        backgroundColor: activo ? const Color(0xFF2D3550) : null,
      ),
      icon: Icon(icono),
    );
  }

  // ------------------------------------------------------------- acciones

  void _pagina(Sesion s, int n) {
    s.fijarPagina(n);
    setState(() {
      _firma = '';
      _itemsFirma = '';
    });
  }

  Future<void> _hoja(PdfDoc d) async {
    final s = Sesion.i;
    setState(() => _ocupado = true);
    try {
      final t = d.tamano(s.paginaActual);
      await d.hojaNueva(s.paginaActual, t[0], t[1]);
      s.fijarPagina(s.paginaActual + 1);
    } catch (e) {
      Sesion.i.aviso('no se pudo agregar la hoja: $e');
    }
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _firma = '';
      _itemsFirma = '';
    });
  }

  Future<void> _borrarUltimo(PdfDoc d) async {
    final s = Sesion.i;
    if (d.cantidadContenido(s.paginaActual) == 0) {
      Sesion.i.aviso('no hay nada agregado en esta página');
      return;
    }
    setState(() => _ocupado = true);
    try {
      await d.borrarUltimo(s.paginaActual);
    } catch (e) {
      Sesion.i.aviso('$e');
    }
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _firma = '';
      _itemsFirma = '';
    });
  }

  Future<void> _deshacer(PdfDoc d) async {
    setState(() => _ocupado = true);
    try {
      await d.deshacer();
    } catch (e) {
      Sesion.i.aviso('$e');
    }
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _firma = '';
      _itemsFirma = '';
    });
  }

  Future<void> _rehacer(PdfDoc d) async {
    setState(() => _ocupado = true);
    try {
      await d.rehacer();
    } catch (e) {
      Sesion.i.aviso('$e');
    }
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _firma = '';
      _itemsFirma = '';
    });
  }

  Future<void> _elegir() async {
    if (_modo == 'imagen' && _imagen != null) {
      setState(() => _modo = '');
      return;
    }
    final ruta = await HostPuente.elegirImagen();
    if (ruta == null || !mounted) return;
    setState(() {
      _imagen = ruta;
      _modo = 'imagen';
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Tocá la hoja para colocar la imagen'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _tap(Offset local, Size size) async {
    final s = Sesion.i;
    final d = s.docActual;
    if (d == null) return;
    if (_modo != 'texto' && _modo != 'imagen') return;
    final t = d.tamano(s.paginaActual);
    final px = (local.dx / size.width).clamp(0.0, 1.0).toDouble() * t[0];
    final py = (1 - local.dy / size.height).clamp(0.0, 1.0).toDouble() * t[1];

    if (_modo == 'texto') {
      final texto = await _pedirTexto();
      if (texto == null) return;
      final limpio = texto.trim();
      if (limpio.isEmpty) return;
      final lineas = limpio.split('\n').length;
      final alto = 14 * 1.2 * lineas + 4;
      final minimo = alto <= t[1] - 4 ? alto : 4.0;
      final y = py.clamp(minimo, t[1] - 4).toDouble();
      await d.agregarTexto(s.paginaActual, px, y, limpio);
      if (!mounted) return;
      setState(() {
        _firma = '';
        _itemsFirma = '';
      });
      return;
    }

    final ruta = _imagen;
    if (ruta == null) {
      Sesion.i.aviso('elegí una imagen primero');
      return;
    }
    await d.agregarImagen(s.paginaActual, ruta, px, py);
    if (!mounted) return;
    setState(() {
      _firma = '';
      _itemsFirma = '';
    });
  }

  Future<String?> _pedirTexto() async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escribir texto'),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Texto…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  // ------------------------------------------------------------- arrastre

  List<double> _rectDe(Map<String, dynamic> item) {
    final r = item['rect'] as List? ?? const [];
    final out = <double>[];
    for (final v in r) {
      out.add((v as num).toDouble());
    }
    while (out.length < 4) {
      out.add(0);
    }
    return out;
  }

  void _panStart(Offset local, Size size) {
    final s = Sesion.i;
    final d = s.docActual;
    if (d == null) return;
    final t = d.tamano(s.paginaActual);
    final px = (local.dx / size.width).clamp(0.0, 1.0).toDouble() * t[0];
    final py = (1 - local.dy / size.height).clamp(0.0, 1.0).toDouble() * t[1];
    for (var i = _items.length - 1; i >= 0; i--) {
      final r = _rectDe(_items[i]);
      if (px >= r[0] && px <= r[2] && py >= r[1] && py <= r[3]) {
        _dragIndex = _items[i]['index'] as int;
        _dragOriginal = r;
        _startX = px;
        _startY = py;
        _ghost = List<double>.from(r);
        setState(() {});
        return;
      }
    }
  }

  void _panUpdate(Offset local, Size size) {
    if (_dragIndex == null || _dragOriginal == null) return;
    final s = Sesion.i;
    final d = s.docActual;
    if (d == null) return;
    final t = d.tamano(s.paginaActual);
    final px = (local.dx / size.width).clamp(0.0, 1.0).toDouble() * t[0];
    final py = (1 - local.dy / size.height).clamp(0.0, 1.0).toDouble() * t[1];
    final dx = px - _startX;
    final dy = py - _startY;
    final r = _dragOriginal!;
    final w = r[2] - r[0];
    final h = r[3] - r[1];
    final x0 = (r[0] + dx).clamp(-w * 0.5, t[0] - w * 0.5).toDouble();
    final y0 = (r[1] + dy).clamp(-h * 0.5, t[1] - h * 0.5).toDouble();
    setState(() {
      _ghost = [x0, y0, x0 + w, y0 + h];
    });
  }

  Future<void> _panEnd() async {
    final idx = _dragIndex;
    final rect = _ghost;
    final original = _dragOriginal;
    final d = Sesion.i.docActual;
    _dragIndex = null;
    _dragOriginal = null;
    _ghost = null;
    if (idx == null || rect == null || original == null || d == null) {
      setState(() {});
      return;
    }
    final quieto = (rect[0] - original[0]).abs() < 0.5 && (rect[1] - original[1]).abs() < 0.5;
    if (quieto) {
      setState(() {});
      return;
    }
    setState(() => _ocupado = true);
    try {
      await d.moverContenido(Sesion.i.paginaActual, idx, rect);
    } catch (e) {
      Sesion.i.aviso('no se pudo mover: $e');
    }
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _firma = '';
      _itemsFirma = '';
    });
  }
}
