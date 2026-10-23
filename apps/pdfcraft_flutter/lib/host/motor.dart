/// Motor d4rt de PdfCraft: carga scripts, registra la API y ejecuta flujos.
///
/// Protocolo del script:
/// - cada flujo `nombre` expone `main() -> Pantalla` (opcionalmente async);
/// - si el flujo tiene acciones, expone `Accion(String id) -> Pantalla |
///   Vista | null` (null = "reescribe la pantalla actual").
///
/// Fuentes: primero intenta el repo público (actualización en caliente),
/// si falla usa los assets embebidos del APK.
library;

import 'dart:convert';
import 'dart:io';

import 'package:d4rt/d4rt.dart' as d4;
import 'package:flutter/services.dart' show rootBundle;

import 'bridge.dart';

/// Repo público de scripts (raw de GitHub). Se pueden subir cambios y la
/// próxima arrancada de la app ya corre la GUI nueva, sin recompilar.
const String kUrlScripts =
    'https://raw.githubusercontent.com/eldeeon20/pdfcraft-gui/main/scripts';

const List<String> kFlujos = ['inicio', 'ver', 'crear', 'editar'];

class Motor {
  Motor._();
  static final Motor i = Motor._();

  final d4.D4rt _d4 = d4.D4rt();
  bool _listo = false;
  final Map<String, String> _fuente = {};
  String proveniencia = 'assets';

  bool get listo => _listo;

  /// Registra bridges + carga fuentes (remota → assets).
  Future<void> preparar() async {
    if (!_listo) {
      registrarBridgesPdf(_d4);
      _listo = true;
    }
    await _cargarFuentes();
  }

  Future<void> _cargarFuentes() async {
    try {
      final remota = <String, String>{};
      for (final f in kFlujos) {
        remota[f] = await _fetch('$kUrlScripts/$f.dart');
      }
      _fuente
        ..clear()
        ..addAll(remota);
      proveniencia = 'remota';
    } catch (_) {
      try {
        final aset = <String, String>{};
        for (final f in kFlujos) {
          aset[f] = await rootBundle.loadString('assets/scripts/$f.dart');
        }
        _fuente
          ..clear()
          ..addAll(aset);
        proveniencia = 'assets';
      } catch (_) {
        proveniencia = 'ninguna';
      }
    }
  }

  Future<String> _fetch(String url) async {
    final c = HttpClient();
    final r = await c.getUrl(Uri.parse(url));
    final resp = await r.close();
    if (resp.statusCode != 200) {
      throw ErrorMotor('no hay $url');
    }
    final texto = utf8.decodeStream(resp);
    if (texto.isEmpty) {
      throw ErrorMotor('vacio $url');
    }
    return texto;
  }

  /// Ejecuta `fn(args...)` dentro del flujo `nombre`.
  Future<Object?> _ejecutar(
    String nombre,
    String fn, {
    List<Object?> args = const [],
  }) async {
    final fuente = _fuente[nombre];
    if (fuente == null) {
      throw ErrorMotor('no hay script para el flujo: $nombre');
    }
    final r = _d4.execute(
      source: fuente,
      name: fn,
      positionalArgs: args,
      timeout: const Duration(minutes: 5),
    );
    return r is Future ? await r : r;
  }

  /// La pantalla completa del flujo.
  Future<Object?> pantalla(String nombre) async {
    return _ejecutar(nombre, 'main');
  }

  /// La reacción del flujo a una acción (Boton id).
  Future<Object?> accion(String nombre, String id) async {
    return _ejecutar(nombre, 'Accion', args: [id]);
  }
}

class ErrorMotor implements Exception {
  ErrorMotor(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}
