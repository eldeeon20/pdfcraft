/// App PdfCraft Android: host mínimo que rinde el árbol del script.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../api.dart';
import 'host_puente.dart';
import 'motor.dart';
import 'render.dart';
import 'sesion.dart';

class PdfApp extends StatelessWidget {
  const PdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    const fondo = Color(0xFF14161F);
    const superficie = Color(0xFF1D2030);
    const acento = Color(0xFFE3B872);
    final esquema = ColorScheme.dark(
      primary: acento,
      onPrimary: const Color(0xFF1A1408),
      secondary: acento,
      onSecondary: const Color(0xFF1A1408),
      surface: superficie,
      error: const Color(0xFFF7768E),
    );
    return MaterialApp(
      title: 'PdfCraft',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: esquema,
        scaffoldBackgroundColor: fondo,
        fontFamilyFallback: const ['Roboto'],
      ),
      home: const PdfHome(),
    );
  }
}

class PdfHome extends StatefulWidget {
  const PdfHome({super.key});

  @override
  State<PdfHome> createState() => _PdfHomeState();
}

class _PdfHomeState extends State<PdfHome> {
  String flujo = 'inicio';
  Object? nodo; // Pantalla (del script)
  bool ocupado = true;
  String error = '';

  @override
  void initState() {
    super.initState();
    AccionFlujo.i.conectar(_presiono);
    HostPuente.abrirHook = _abrirArchivo;
    HostPuente.guardarHook = _guardarComo;
    HostPuente.imagenHook = _elegirImagen;
    _arranco();
  }

  Future<void> _arranco() async {
    try {
      await Motor.i.preparar();
      await _irA('inicio');
    } catch (e) {
      setState(() {
        ocupado = false;
        error = '$e';
      });
    }
  }

  Future<void> _irA(String nombre) async {
    setState(() {
      flujo = nombre;
      ocupado = true;
      error = '';
    });
    try {
      final r = await Motor.i.pantalla(nombre);
      setState(() {
        nodo = r;
        ocupado = false;
      });
    } catch (e) {
      setState(() {
        ocupado = false;
        error = '$e';
      });
    }
    if (mounted) _mostrarAviso();
  }

  Future<void> _presiono(String id) async {
    if (ocupado) return;
    setState(() => ocupado = true);
    try {
      final r = await Motor.i.accion(flujo, id);
      if (r is Vista) {
        await _irA(r.id);
        return;
      }
      setState(() {
        if (r != null) {
          nodo = r;
        }
        ocupado = false;
      });
    } catch (e) {
      setState(() => ocupado = false);
      Sesion.i.aviso('error: $e');
      if (mounted) _mostrarAviso();
      return;
    }
    if (mounted) {
      setState(() {});
      _mostrarAviso();
    }
  }

  void _mostrarAviso() {
    final m = Sesion.i.mensajeActual;
    if (m.isEmpty || !mounted) return;
    Sesion.i.aviso('');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      duration: const Duration(seconds: 3),
    ));
  }

  // ---------------------------------------------------------------- host

  Future<PdfDoc?> _abrirArchivo() async {
    final f = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final ruta = f?.files.single.path;
    if (ruta == null) return null;
    final nombre = ruta.split('/').last;
    try {
      final d = await PdfDoc.abrir(ruta);
      Sesion.i.fijarDoc(d);
      Sesion.i.archivoFue(nombre);
      Sesion.i.aviso('abierto: $nombre (${d.paginas} páginas)');
      return d;
    } catch (e) {
      Sesion.i.aviso('no se pudo abrir: $e');
      return null;
    }
  }

  Future<String?> _guardarComo() async {
    final d = Sesion.i.docActual;
    if (d == null) {
      Sesion.i.aviso('no hay documento para guardar');
      return null;
    }
    final nombre = Sesion.i.nombreArchivo.isEmpty ? 'pdfcraft.pdf' : Sesion.i.nombreArchivo;
    final seguro = nombre.toLowerCase().endsWith('.pdf') ? nombre : '$nombre.pdf';
    String temporal;
    try {
      final dir = await getTemporaryDirectory();
      temporal = '${dir.path}/$seguro';
      await d.guardar(temporal);
    } catch (e) {
      Sesion.i.aviso('no se pudo preparar el PDF: $e');
      return null;
    }
    final bytes = await File(temporal).readAsBytes();
    try {
      final ruta = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar PDF',
        fileName: seguro,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );
      if (ruta != null) {
        Sesion.i.aviso('guardado en $ruta');
        await _mostrarRuta(ruta);
        return ruta;
      }
    } catch (e) {
      Sesion.i.aviso('el selector falló: $e');
    }
    try {
      Directory? dir;
      try {
        dir = await getExternalStorageDirectory();
      } catch (_) {}
      dir ??= await getApplicationDocumentsDirectory();
      final carpeta = Directory('${dir.path}/PdfCraft');
      await carpeta.create(recursive: true);
      final ruta = '${carpeta.path}/$seguro';
      await File(ruta).writeAsBytes(bytes, flush: true);
      Sesion.i.aviso('guardado en $ruta');
      await _mostrarRuta(ruta);
      return ruta;
    } catch (e) {
      Sesion.i.aviso('no se pudo guardar: $e');
      return null;
    }
  }

  Future<String?> _elegirImagen() async {
    final f = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    final ruta = f?.files.single.path;
    if (ruta == null) return null;
    Sesion.i.fijarCampo('imagen', ruta);
    Sesion.i.aviso('imagen elegida: ${ruta.split('/').last}');
    return ruta;
  }

  Future<void> _mostrarRuta(String ruta) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PDF guardado'),
        content: SelectableText('Ruta:\n$ruta'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14161F),
      appBar: _barra(),
      body: _cuerpo(),
    );
  }

  PreferredSizeWidget _barra() {
    final p = nodo is Pantalla ? nodo! as Pantalla : null;
    final botones = [
      for (final m in (p?.menu ?? const <Object?>[])) if (m is Boton) m
    ];
    return AppBar(
      backgroundColor: const Color(0xFF1A1C2A),
      title: Text(
        p?.titulo ?? 'PdfCraft',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      ),
      actions: [
        for (final b in botones.where((b) => b.icono.isNotEmpty))
          IconButton(
            tooltip: b.etiqueta,
            icon: Icon(iconoDe(b.icono)),
            onPressed: ocupado ? null : () => _presiono(b.id),
          ),
        if (botones.isNotEmpty)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (id) => _presiono(id),
            itemBuilder: (_) => [
              for (final b in botones)
                PopupMenuItem(value: b.id, child: Text(b.etiqueta)),
            ],
          ),
        if (flujo != 'inicio')
          IconButton(
            tooltip: 'Inicio',
            icon: const Icon(Icons.home_outlined),
            onPressed: ocupado ? null : () => _irA('inicio'),
          ),
      ],
    );
  }

  Widget _cuerpo() {
    if (ocupado) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 42, color: Color(0xFFF7768E)),
            const SizedBox(height: 16),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => _irA('inicio'),
              child: const Text('Volver'),
            ),
          ],
        ),
      );
    }
    final pantalla = nodo;
    if (pantalla is! Pantalla) {
      return const Center(child: Text('El script no devolvió una Pantalla'));
    }
    return _pantalla(pantalla);
  }

  Widget _pantalla(Pantalla p) {
    final hijos = renderLista(p.cuerpo);
    if (!p.caja) {
      // Visor, sin márgenes: ocupa la pantalla.
      return Column(children: [Expanded(child: hijos.isEmpty ? const SizedBox() : hijos.first)]);
    }
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos),
            ),
          ),
        ),
      ),
    );
  }
}
