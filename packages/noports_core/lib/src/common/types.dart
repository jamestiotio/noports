import 'package:noports_core/sshrv.dart';

typedef SshrvGenerator<T> = SSHRV<T> Function(String, int, {int localSshdPort});

enum SupportedSshClient {
  exec(cliArg: '/usr/bin/ssh'),
  dart(cliArg: 'dart');

  final String _cliArg;
  const SupportedSshClient({required String cliArg}) : _cliArg = cliArg;

  factory SupportedSshClient.fromString(String cliArg) {
    return SupportedSshClient.values.firstWhere(
      (arg) => arg._cliArg == cliArg,
      orElse: () => throw ArgumentError('Unsupported SSH client: $cliArg'),
    );
  }

  @override
  String toString() => _cliArg;
}

enum SupportedSshAlgorithm {
  ed25519(cliArg: 'ssh-ed25519'),
  rsa(cliArg: 'ssh-rsa');

  final String _cliArg;
  const SupportedSshAlgorithm({required String cliArg}) : _cliArg = cliArg;

  factory SupportedSshAlgorithm.fromString(String cliArg) {
    return SupportedSshAlgorithm.values.firstWhere(
      (arg) => arg._cliArg == cliArg,
      orElse: () => throw ArgumentError('Unsupported SSH algorithm: $cliArg'),
    );
  }

  @override
  String toString() => _cliArg;
}
