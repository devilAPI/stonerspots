// Whether Flutter GPU can be used. `package:flutter_gpu` needs `dart:ffi`,
// which the web does not have; there it is never available.
export 'flutter_gpu_check_native.dart'
    if (dart.library.js_interop) 'flutter_gpu_check_web.dart';
