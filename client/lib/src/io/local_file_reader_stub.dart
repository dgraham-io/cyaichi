import 'local_file_reader.dart';

class StubLocalFileReader implements LocalFileReader {
  @override
  Future<String> readText(String path) {
    throw UnsupportedError(
      'Reading local files is not supported on this platform.',
    );
  }
}

LocalFileReader createPlatformLocalFileReader() => StubLocalFileReader();
