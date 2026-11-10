import 'package:flutter_gpu/gpu.dart' as gpu;

/// Whether Flutter GPU is switched on and has a context (Impeller, and the
/// app config enables it).
bool flutterGpuAvailable() {
  try {
    gpu.gpuContext;
    return true;
  } on Object {
    return false;
  }
}
