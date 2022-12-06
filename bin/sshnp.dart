// dart packages
import 'dart:io';
import 'package:logging/src/level.dart';
// atPlatform packages
import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
// external packages
import 'package:args/args.dart';
import 'package:uuid/uuid.dart';
// local packages
import 'package:sshnoports/home_directory.dart';
import 'package:sshnoports/check_non_ascii.dart';
import 'package:sshnoports/cleanup_sshnp.dart';
import 'package:sshnoports/check_file_exists.dart';

void main(List<String> args) async {
  final AtSignLogger _logger = AtSignLogger(' sshnp ');
  _logger.hierarchicalLoggingEnabled = true;
  _logger.logger.level = Level.SHOUT;

  var uuid = Uuid();
  String sessionId = uuid.v4();

  ProcessSignal.sigint.watch().listen((signal) async {
    await cleanUp(sessionId, _logger);
    exit(0);
  });

  var parser = ArgParser();
  // Basic arguments
  parser.addOption('key-file',
      abbr: 'k', mandatory: false, help: 'Sending atSign\'s atKeys file if not in ~/.atsign/keys/');
  parser.addOption('from', abbr: 'f', mandatory: true, help: 'Sending atSign');
  parser.addOption('to', abbr: 't', mandatory: true, help: 'Send a notification to this atSign');
  parser.addOption('device',
      abbr: 'd', mandatory: false, defaultsTo: "default", help: 'Send a notification to this device');
  parser.addOption('host',
      abbr: 'h', mandatory: true, help: 'FQDN Hostname e.g example.com or IP address to connect back to');
  parser.addOption('port', abbr: 'p', mandatory: false, defaultsTo: '22', help: 'TCP port to connect back to');
  parser.addOption('local-port',
      abbr: 'l', defaultsTo: '2222', mandatory: false, help: 'Reverse ssh port to listen on, on your local machine');
  parser.addOption('ssh-public-key',
      abbr: 's',
      defaultsTo: 'false',
      mandatory: false,
      help: 'Public key file from ~/.ssh to be apended to authorized_hosts on the remote device');
  parser.addMultiOption('local-ssh-options', abbr: 'o', help: 'Add these commands to the local ssh command');
  parser.addFlag('verbose', abbr: 'v', help: 'More logging');

  // Check the arguments
  dynamic results;
  String? username;
  String atsignFile;
  String fromAtsign = 'unknown';
  String toAtsign = 'unknown';
  String? homeDirectory = getHomeDirectory();
  String device = "";
  String nameSpace = '';
  String port;
  String host = "127.0.0.1";
  String localPort;
  String sshString = "";
  String sshHomeDirectory = "";
  String sendSshPublicKey = "";
  List<String> localSshOptions = [];
  int counter = 0;
  bool ack = false;
  // In the future (perhaps) we can send other commands
  // Perhaps OpenVPN or shell commands
  String sendCommand = 'sshd';

  try {
    // Arg check
    results = parser.parse(args);

    // Do we have a username ?
    Map<String, String> envVars = Platform.environment;
    if (Platform.isLinux || Platform.isMacOS) {
      username = envVars['USER'];
    } else if (Platform.isWindows) {
      username = envVars['USERPROFILE'];
    }
    if (username == null) {
      throw ('\nUnable to determine your username: please set environment variable\n\n');
    }
    if (homeDirectory == null) {
      throw ('\nUnable to determine your home directory: please set environment variable\n\n');
    }
    // Setup ssh keys location
    sshHomeDirectory = homeDirectory + "/.ssh/";
    if (Platform.isWindows) {
      sshHomeDirectory = homeDirectory + '\\.ssh\\';
    }

    // Find atSign key file
    fromAtsign = results['from'];
    toAtsign = results['to'];
    if (results['key-file'] != null) {
      atsignFile = results['key-file'];
    } else {
      atsignFile = '${fromAtsign}_key.atKeys';
      atsignFile = '$homeDirectory/.atsign/keys/$atsignFile';
    }
    // Check atKeyFile selected exists
    if (!await fileExists(atsignFile)) {
      throw ('\n Unable to find .atKeys file : $atsignFile');
    }

// Get the other easy options
    host = results['host'];
    port = results['port'];
    localPort = results['local-port'];
    localSshOptions = results['local-ssh-options'];
// Check device string only contains ascii
//
    if (checkNonAscii(results['device'])) {
      throw ('\nDevice name can only contain alphanumeric characters with a max length of 15');
    }
    // Add a namespace separater just cause its neater.
    device = results['device'] + ".";
    nameSpace = '${device}sshnp';

// Check the public key if the option was selected
    sendSshPublicKey = results['ssh-public-key'];
    if ((sendSshPublicKey != 'false')) {
      sendSshPublicKey = '$sshHomeDirectory$sendSshPublicKey';
      if (!await fileExists(sendSshPublicKey)) {
        throw ('\n Unable to find ssh public key file : $sendSshPublicKey');
      }
      if (!sendSshPublicKey.endsWith('.pub')) {
        throw ('\n The ssh public key should have a ".pub" extention');
      }
    }
  } catch (e) {
    print(parser.usage);
    print(e);
    exit(1);
  }

  await Process.run('ssh-keygen', ['-t', 'rsa', '-b', '4096', '-f', '${sessionId}_rsa', '-q', '-N', ''],
      workingDirectory: sshHomeDirectory);
  String sshPublicKey = await File('$sshHomeDirectory${sessionId}_rsa.pub').readAsString();
  String sshPrivateKey = await File('$sshHomeDirectory${sessionId}_rsa').readAsString();

  // Set up a safe authorized_keys file, for the reverse ssh tunnel
  File('${sshHomeDirectory}authorized_keys').writeAsStringSync(
      'command="echo \\"ssh session complete\\";sleep 20",PermitOpen="localhost:22" ${sshPublicKey.trim()} $sessionId\n',
      mode: FileMode.append);

  // Now on to the atPlatform startup
  AtSignLogger.root_level = 'SHOUT';
  if (results['verbose']) {
    _logger.logger.level = Level.INFO;

    AtSignLogger.root_level = 'INFO';
  }

  //onboarding preference builder can be used to set onboardingService parameters
  AtOnboardingPreference atOnboardingConfig = AtOnboardingPreference()
    //..qrCodePath = '<location of image>'
    ..hiveStoragePath = '$homeDirectory/.sshnp/$fromAtsign/storage'
    ..namespace = device + 'sshnp'
    ..downloadPath = '$homeDirectory/.sshnp/files'
    ..isLocalStoreRequired = true
    ..commitLogPath = '$homeDirectory/.sshnp/$fromAtsign/storage/commitLog'
    //..cramSecret = '<your cram secret>';
    ..atKeysFilePath = atsignFile;

  AtOnboardingService onboardingService = AtOnboardingServiceImpl(fromAtsign, atOnboardingConfig);

  await onboardingService.authenticate();

  var atClient = await onboardingService.getAtClient();

  AtClientManager atClientManager = AtClientManager.getInstance();

  NotificationService notificationService = atClientManager.notificationService;

  bool syncComplete = false;
  void onSyncDone(syncResult) {
    _logger.info("syncResult.syncStatus: ${syncResult.syncStatus}");
    _logger.info("syncResult.lastSyncedOn ${syncResult.lastSyncedOn}");
    syncComplete = true;
  }

  // Wait for initial sync to complete
  _logger.info("Waiting for initial sync");
  syncComplete = false;
  atClientManager.syncService.sync(onDone: onSyncDone);
  while (!syncComplete) {
    await Future.delayed(Duration(milliseconds: 100));
  }

  notificationService.subscribe(regex: '$sessionId.$nameSpace@', shouldDecrypt: true).listen(((notification) async {
    String keyAtsign = notification.key;
    keyAtsign = keyAtsign.replaceAll(notification.to + ':', '');
    keyAtsign = keyAtsign.replaceAll('.' + device + '.' + 'sshnp' + notification.from, '');
    _logger.info('Received $keyAtsign notification');
    if (notification.value == 'connected') {
      _logger.info('Session $sessionId connected succesfully');
      // Give ssh/sshd a little time to get everything in place
      //   await Future.delayed(Duration(milliseconds: 250));
      ack = true;
    } else {
      stderr.write('Remote Error: ${notification.value}');
      ack = true;
    }
  }));

  var metaData = Metadata()
    ..isPublic = false
    ..isEncrypted = true
    ..namespaceAware = true;

  var atKey = AtKey()
    ..key = "username"
    ..sharedBy = toAtsign
    ..sharedWith = fromAtsign
    ..namespace = nameSpace
    ..metadata = metaData;
  var toAtsignUsername = await atClient?.get(atKey);

  var remoteUsername = toAtsignUsername?.value;

  metaData = Metadata()
    ..isPublic = false
    ..isEncrypted = true
    ..namespaceAware = true
    ..ttr = -1
    ..ttl = 10000;

  var key = AtKey()
    ..key = 'privateKey'
    ..sharedBy = fromAtsign
    ..sharedWith = toAtsign
    ..namespace = nameSpace
    ..metadata = metaData;

  try {
    await notificationService.notify(NotificationParams.forUpdate(key, value: sshPrivateKey),
        onSuccess: (notification) {
      _logger.info('SUCCESS:' + notification.toString());
    }, onError: (notification) {
      _logger.info('ERROR:' + notification.toString());
    });
  } catch (e) {
    print(e.toString());
  }

  metaData = Metadata()
    ..isPublic = false
    ..isEncrypted = true
    ..namespaceAware = true
    ..ttr = -1
    ..ttl = 10000;

  key = AtKey()
    ..key = 'sshPublicKey'
    ..sharedBy = fromAtsign
    ..sharedWith = toAtsign
    ..metadata = metaData;

  if (sendSshPublicKey != 'false') {
    try {
      String toSshPublicKey = await File(sendSshPublicKey).readAsString();
      if (!toSshPublicKey.startsWith('ssh-rsa')) {
        throw ('$sshHomeDirectory$sendSshPublicKey does not look like a public key file');
      }
      await notificationService.notify(NotificationParams.forUpdate(key, value: toSshPublicKey),
          onSuccess: (notification) {
        _logger.info('SUCCESS:' + notification.toString());
      }, onError: (notification) {
        _logger.info('ERROR:' + notification.toString());
      });
    } catch (e) {
      print("Error openning or validating public key file or sending to remote atSign: " + e.toString());
      await cleanUp(sessionId, _logger);
      exit(0);
    }
  }

  metaData = Metadata()
    ..isPublic = false
    ..isEncrypted = true
    ..namespaceAware = true
    ..ttr = -1
    ..ttl = 10000;

  key = AtKey()
    ..key = sendCommand
    ..sharedBy = fromAtsign
    ..sharedWith = toAtsign
    ..metadata = metaData;

  if (sendCommand == 'sshd') {
    // Local port, port of sshd , username , hostname
    sshString = '$localPort $port $username $host $sessionId';
  }

  try {
    await notificationService.notify(NotificationParams.forUpdate(key, value: sshString), onSuccess: (notification) {
      _logger.info('SUCCESS:' + notification.toString() + ' ' + sshString);
    }, onError: (notification) {
      _logger.info('ERROR:' + notification.toString() + ' ' + sshString);
    });
  } catch (e) {
    print(e.toString());
  }

  // Before we clean up we need to make sure that the reverse ssh made the connection.
  // Or that if it had a problem what the problem was, or timeout and explain why.

  // Timer to timeout after 10 Secs or after the Ack of connected/Errors
  while (!ack) {
    await Future.delayed(Duration(milliseconds: 100));
    counter++;
    if (counter == 100) {
      ack = true;
    }
  }

  // Clean Up the files we created
  await cleanUp(sessionId, _logger);

  // print out base ssh command
  // If we had a Public key include the private key in the command line
  // By removing the .pub extn
  if (sendSshPublicKey != 'false') {
    stdout.write(
        "ssh -p $localPort $remoteUsername@localhost -i ${sendSshPublicKey.replaceFirst(RegExp(r'.pub$'), '')} ");
  } else {
    stdout.write("ssh -p $localPort $remoteUsername@localhost ");
  }
  // print out optional arguments
  for (var argument in localSshOptions) {
    stdout.write(argument + " ");
  }
  // Print the  return
  stdout.write('\n');
  exit(0);
}
