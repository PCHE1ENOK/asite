// Воркер базы для веб-сборки: tool/build_web.sh компилирует его в
// web/drift_worker.js той же версией drift, что и приложение.
import 'package:drift/wasm.dart';

void main() => WasmDatabase.workerMainForOpen();
