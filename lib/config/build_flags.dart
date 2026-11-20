import 'package:flutter/foundation.dart';

/// Compile-time build flags configured via `--dart-define`
const bool kEnableDiagnostics =
    bool.fromEnvironment('ENABLE_DIAGNOSTICS', defaultValue: false);

/// Whether diagnostic tools, system logs, and upload flows are enabled.
/// Active in debug builds or when `--dart-define=ENABLE_DIAGNOSTICS=true` is passed.
const bool kIsDiagnosticsEnabled = kEnableDiagnostics || kDebugMode;
