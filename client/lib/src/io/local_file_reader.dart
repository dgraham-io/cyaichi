import 'local_file_reader_stub.dart'
    if (dart.library.io) 'local_file_reader_io.dart';

abstract class LocalFileReader {
  Future<String> readText(String path);
}

LocalFileReader createLocalFileReader() => createPlatformLocalFileReader();
