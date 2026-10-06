import 'dart:io';

Future<void> main(List<String> arguments) async {
  final schema = arguments.single;
  await _run(['run', 'pigeon', '--input', schema]);

  final swiftFile = File(
    'ios/secure_content/Sources/secure_content/SecureContentApi.g.swift',
  );
  final source = swiftFile.readAsStringSync();
  const signature =
      'func onEvent(event eventArg: SecureEvent, '
      'completion: @escaping (Result<Void, PigeonError>) -> Void)';
  final occurrences = source.split(signature).length - 1;
  if (occurrences != 2) {
    throw StateError(
      'Expected exactly two Pigeon onEvent callback signatures; '
      'found $occurrences. Review the Swift sendability adaptation '
      'before updating the generator.',
    );
  }
  swiftFile.writeAsStringSync(
    source.replaceAll(
      signature,
      signature.replaceFirst('@escaping ', '@escaping @Sendable '),
    ),
  );
  await _run(['format', 'lib/src/pigeon/secure_content_api.g.dart']);
}

Future<void> _run(List<String> arguments) async {
  final result = await Process.run(Platform.resolvedExecutable, arguments);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    exit(result.exitCode);
  }
}
