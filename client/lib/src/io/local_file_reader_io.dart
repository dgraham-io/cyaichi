import 'dart:io';

import 'local_file_reader.dart';

class IoLocalFileReader implements LocalFileReader {
  @override
  Future<String> readText(String path) {
    return File(path).readAsString();
  }
}

LocalFileReader createPlatformLocalFileReader() => IoLocalFileReader();
