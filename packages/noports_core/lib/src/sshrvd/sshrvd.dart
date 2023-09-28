import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';
import 'package:noports_core/src/sshrvd/sshrvd_impl.dart';
import 'package:noports_core/src/sshrvd/sshrvd_params.dart';

abstract class SSHRVD {
  static const String namespace = 'sshrvd';

  abstract final AtSignLogger logger;
  abstract AtClient atClient;
  abstract final String atSign;
  abstract final String homeDirectory;
  abstract final String atKeysFilePath;
  abstract final String managerAtsign;
  abstract final String ipAddress;
  abstract final bool snoop;

  /// true once [init] has completed
  @visibleForTesting
  bool initialized = false;

  factory SSHRVD(
      {
      // final fields
      required AtClient atClient,
      required String atSign,
      required String homeDirectory,
      required String atKeysFilePath,
      required String managerAtsign,
      required String ipAddress,
      required bool snoop}) {
    return SSHRVDImpl(
      atClient: atClient,
      atSign: atSign,
      homeDirectory: homeDirectory,
      atKeysFilePath: atKeysFilePath,
      managerAtsign: managerAtsign,
      ipAddress: ipAddress,
      snoop: snoop,
    );
  }

  static Future<SSHRVD> fromCommandLineArgs(List<String> args,
      {AtClient? atClient,
      FutureOr<AtClient> Function(SSHRVDParams)? atClientGenerator,
      void Function(Object, StackTrace)? usageCallback}) async {
    return SSHRVDImpl.fromCommandLineArgs(
      args,
      atClient: atClient,
      atClientGenerator: atClientGenerator,
      usageCallback: usageCallback
    );
  }

  Future<void> init();
  Future<void> run();
}
