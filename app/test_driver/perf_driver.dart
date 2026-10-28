// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:integration_test/integration_test_driver.dart';

/// Prints the frame timings `integration_test/perf_test.dart` collected.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    // timelines are large: written to build/, see writeResponseData
    if (data.keys.any((k) => k.endsWith('-timeline'))) {
      await writeResponseData(data, testOutputFilename: 'perf_timeline');
      return;
    }
    print(const JsonEncoder.withIndent('  ').convert(data));
  },
);
