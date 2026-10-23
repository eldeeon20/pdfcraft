// Host mínimo de PdfCraft Android: carga el .so (core) y la GUI d4rt (scripts).
library;

import 'package:flutter/material.dart';
import 'host/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PdfApp());
}
