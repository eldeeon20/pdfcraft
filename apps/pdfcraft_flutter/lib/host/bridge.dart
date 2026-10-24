/// Registro de bridges en d4rt: lo que el script ve.
///
/// Biblioteca con la que los scripts importan:
/// ```dart
/// import 'package:pdfcraft_flutter/api.dart';
/// ```
/// Funciones sin import: `yo()`, `aviso()`, `versionCore()`, `abrir()`,
/// `crear()`, `guardarComo()`.
///
/// Regla: nada de dart:ffi ni Flutter desde el script; solo clases bridged.
library;

import 'package:d4rt/d4rt.dart' as d4;

import '../api.dart';
import 'host_puente.dart';

const String uriApi = 'package:pdfcraft_flutter/api.dart';

void _registra(d4.D4rt interprete, d4.BridgedClass clase) {
  interprete.registerBridgedClass(clase, uriApi);
}

d4.BridgedConstructorCallable _ctor(d4.BridgedConstructorCallable f) => f;

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double _flt(dynamic v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

String _str(dynamic v, [String d = '']) => v?.toString() ?? d;

bool _bool(dynamic v, [bool d = false]) {
  if (v is bool) return v;
  return d;
}

/// Desenvuelve instancias bridged (llegan envueltas en BridgedInstance).
Object? des(Object? v) {
  if (v is d4.BridgedInstance) return des(v.nativeObject);
  if (v is List) return [for (final x in v) des(x)];
  return v;
}

/// Registra toda la API. Idempotente: llamar una sola vez por intérprete.
void registrarBridgesPdf(d4.D4rt interprete) {
  // ---------------------------------------------------------------- global
  interprete.registertopLevelFunction(
    'yo',
    (_, __, ___, ____) => Sesion.i,
    signature: 'Sesion yo()',
  );
  interprete.registertopLevelFunction(
    'aviso',
    (_, args, __, ___) {
      Sesion.i.aviso(_str(args.isNotEmpty ? args[0] : ''));
      return null;
    },
    signature: 'void aviso(String texto)',
  );
  interprete.registertopLevelFunction(
    'versionCore',
    (_, __, ___, ____) => versionCore(),
    signature: 'String versionCore()',
  );
  interprete.registertopLevelFunction(
    'abrir',
    (_, __, ___, ____) => HostPuente.abrir(),
    signature: 'Future<PdfDoc?> abrir()',
  );
  interprete.registertopLevelFunction(
    'crear',
    (_, args, __, ___) => PdfDoc.crear(
      _str(args.isNotEmpty ? args[0] : 'Documento'),
      _str(args.length > 1 ? args[1] : ''),
    ),
    signature: 'Future<PdfDoc> crear(String titulo, String texto)',
  );
  interprete.registertopLevelFunction(
    'guardarComo',
    (_, __, ___, ____) => HostPuente.guardarComo(),
    signature: "Future<String?> guardarComo()  // usa yo().doc",
  );
  interprete.registertopLevelFunction(
    'elegirImagen',
    (_, __, ___, ____) => HostPuente.elegirImagen(),
    signature: 'Future<String?> elegirImagen()',
  );

  // ---------------------------------------------------------------- PdfDoc
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: PdfDoc,
      name: 'PdfDoc',
      constructors: const {},
      getters: {
        'id': (_, t) => (t as PdfDoc).id,
        'titulo': (_, t) => (t as PdfDoc).titulo,
        'paginas': (_, t) => (t as PdfDoc).paginas,
      },
      methods: {
        'png': (_, t, p, __) => (t as PdfDoc).png(_int(p.isEmpty ? 1 : p[0]),
            _flt(p.length > 1 ? p[1] : 144)),
        'textoDe': (_, t, p, __) =>
            (t as PdfDoc).textoDe(_int(p.isEmpty ? 1 : p[0])),
        'rotar': (_, t, p, __) => (t as PdfDoc)
            .rotar(_int(p.isEmpty ? 1 : p[0]), _int(p.length > 1 ? p[1] : 90)),
        'borrar': (_, t, p, __) => (t as PdfDoc).del(_int(p.isEmpty ? 1 : p[0])),
        'mover': (_, t, p, __) => (t as PdfDoc)
            .mover(_int(p.isEmpty ? 1 : p[0]), _int(p.length > 1 ? p[1] : 1)),
        'duplicar': (_, t, p, __) =>
            (t as PdfDoc).duplicar(_int(p.isEmpty ? 1 : p[0])),
        'hojaNueva': (_, t, p, __) => (t as PdfDoc).hojaNueva(
            _int(p.isEmpty ? 0 : p[0]),
            _flt(p.length > 1 ? p[1] : 612),
            _flt(p.length > 2 ? p[2] : 792)),
        'guardar': (_, t, p, __) =>
            (t as PdfDoc).guardar(_str(p.isEmpty ? '' : p[0])),
        'tamano': (_, t, p, __) =>
            (t as PdfDoc).tamano(_int(p.isEmpty ? 1 : p[0])),
        'anchoPagina': (_, t, p, __) =>
            (t as PdfDoc).anchoPagina(_int(p.isEmpty ? 1 : p[0])),
        'altoPagina': (_, t, p, __) =>
            (t as PdfDoc).altoPagina(_int(p.isEmpty ? 1 : p[0])),
        'cantidadContenido': (_, t, p, __) =>
            (t as PdfDoc).cantidadContenido(_int(p.isEmpty ? 1 : p[0])),
        'agregarTexto': (_, t, p, n) => (t as PdfDoc).agregarTexto(
            _int(p.isEmpty ? 1 : p[0]),
            _flt(p.length > 1 ? p[1] : 0),
            _flt(p.length > 2 ? p[2] : 0),
            _str(p.length > 3 ? p[3] : ''),
            ancho: _flt(n['ancho'] ?? 0),
            tam: _flt(n['tam'] ?? 14),
            negrita: _bool(n['negrita'], false),
            italica: _bool(n['italica'], false),
            alineacion: _str(n['alineacion'], 'left'),
            familia: _str(n['familia'], 'helvetica')),
        'agregarImagen': (_, t, p, n) => (t as PdfDoc).agregarImagen(
            _int(p.isEmpty ? 1 : p[0]),
            _str(p.length > 1 ? p[1] : ''),
            _flt(p.length > 2 ? p[2] : 0),
            _flt(p.length > 3 ? p[3] : 0),
            ancho: _flt(n['ancho'] ?? 180),
            alto: _flt(n['alto'] ?? 180)),
        'borrarUltimo': (_, t, p, __) =>
            (t as PdfDoc).borrarUltimo(_int(p.isEmpty ? 1 : p[0])),
        'borrarContenido': (_, t, p, __) => (t as PdfDoc).borrarContenido(
            _int(p.isEmpty ? 1 : p[0]), _int(p.length > 1 ? p[1] : 0)),
        'cerrar': (_, t, __, ___) {
          (t as PdfDoc).cerrar();
          return null;
        },
      },
    ),
  );

  // ---------------------------------------------------------------- Sesion
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Sesion,
      name: 'Sesion',
      constructors: const {},
      getters: {
        'doc': (_, t) => (t as Sesion).docActual,
        'pagina': (_, t) => (t as Sesion).paginaActual,
        'dpi': (_, t) => (t as Sesion).dpiActual,
        'mensaje': (_, t) => (t as Sesion).mensajeActual,
        'archivo': (_, t) => (t as Sesion).nombreArchivo,
        'hay_doc': (_, t) => (t as Sesion).hay_doc,
        'paginas': (_, t) => (t as Sesion).docActual?.paginas ?? 0,
      },
      setters: {
        'doc': (_, t, v) => (t as Sesion).fijarDoc(des(v) as PdfDoc?),
        'pagina': (_, t, v) => (t as Sesion).fijarPagina(_int(v)),
        'dpi': (_, t, v) => (t as Sesion).fijarDpi(_flt(v)),
        'mensaje': (_, t, v) => (t as Sesion).aviso(_str(v)),
      },
      methods: {
        'campo': (_, t, p, __) => (t as Sesion).campo(_str(p.isEmpty ? '' : p[0])),
        'fijarCampo': (_, t, p, __) {
          (t as Sesion).fijarCampo(_str(p.isEmpty ? '' : p[0]),
              _str(p.length > 1 ? p[1] : ''));
          return null;
        },
        'fijarDoc': (_, t, p, __) {
          (t as Sesion).fijarDoc(des(p.isEmpty ? null : p[0]) as PdfDoc?);
          return null;
        },
        'fijarPagina': (_, t, p, __) {
          (t as Sesion).fijarPagina(_int(p.isEmpty ? 1 : p[0]));
          return null;
        },
        'fijarDpi': (_, t, p, __) {
          (t as Sesion).fijarDpi(_flt(p.isEmpty ? 144 : p[0]));
          return null;
        },
        'archivoFue': (_, t, p, __) {
          (t as Sesion).archivoFue(_str(p.isEmpty ? '' : p[0]));
          return null;
        },
      },
    ),
  );

  // ---------------------------------------------------------------- kit UI
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Titulo,
      name: 'Titulo',
      constructors: {
        '': _ctor((_, p, n) => Titulo(_str(p.isEmpty ? 'Título' : p[0]))),
      },
    ),
  );
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Texto,
      name: 'Texto',
      constructors: {
        '': _ctor((_, p, n) => Texto(_str(p.isEmpty ? '' : p[0]))),
      },
    ),
  );
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Boton,
      name: 'Boton',
      constructors: {
        '': _ctor((_, p, n) => Boton(_str(p.isEmpty ? 'Ok' : p[0]),
            _str(p.length > 1 ? p[1] : 'ok'),
            primario: _bool(n['primario'], true),
            icono: _str(n['icono'], ''))),
      },
    ),
  );
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Entrada,
      name: 'Entrada',
      constructors: {
        '': _ctor((_, p, n) => Entrada(_str(p.isEmpty ? 'campo0' : p[0]),
            _str(p.length > 1 ? p[1] : ''),
            multilinea: _bool(n['multilinea'], false))),
      },
    ),
  );
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Fila,
      name: 'Fila',
      constructors: {
        '': _ctor((_, p, n) => Fila(
            des(p.isEmpty ? const [] : p[0]) as List<Object?>? ?? const [],
            reparto: _bool(n['reparto'], false))),
      },
    ),
  );
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Columna,
      name: 'Columna',
      constructors: {
        '': _ctor((_, p, n) => Columna(
            des(p.isEmpty ? const [] : p[0]) as List<Object?>? ?? const [])),
      },
    ),
  );
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Panel,
      name: 'Panel',
      constructors: {
        '': _ctor((_, p, n) => Panel(
            des(p.isEmpty ? const [] : p[0]) as List<Object?>? ?? const [])),
      },
    ),
  );
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Espacio,
      name: 'Espacio',
      constructors: {
        '': _ctor((_, p, __) =>
            Espacio(p.isEmpty ? 16.0 : _flt(p[0]))),
      },
    ),
  );
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Visor,
      name: 'Visor',
      constructors: {
        '': _ctor((_, __, ___) => Visor()),
      },
    ),
  );
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Lienzo,
      name: 'Lienzo',
      constructors: {
        '': _ctor((_, __, ___) => Lienzo()),
      },
    ),
  );
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Pantalla,
      name: 'Pantalla',
      constructors: {
        '': _ctor((_, p, n) => Pantalla(
            _str(p.isEmpty ? 'PdfCraft' : p[0]),
            p.length > 1 ? des(p[1]) : null,
            caja: _bool(n['caja'] ?? true, true),
            menu: des(n['menu']) as List<Object?>? ?? const [])),
      },
    ),
  );
  _registra(
    interprete,
    d4.BridgedClass(
      nativeType: Vista,
      name: 'Vista',
      constructors: {
        '': _ctor((_, p, __) => Vista(_str(p.isEmpty ? 'inicio' : p[0]))),
      },
    ),
  );
}
