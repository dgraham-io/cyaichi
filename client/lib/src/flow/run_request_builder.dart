import 'package:client/src/flow/primary_output.dart';

class RunRequestParams {
  const RunRequestParams({
    required this.inputFile,
    required this.outputFile,
    required this.primaryWriteNodeId,
  });

  final String inputFile;
  final String outputFile;
  final String primaryWriteNodeId;
}

class RunRequestValidation {
  const RunRequestValidation({
    this.params,
    this.errorMessage,
    this.needsPrimarySelection = false,
  });

  final RunRequestParams? params;
  final String? errorMessage;
  final bool needsPrimarySelection;

  bool get isValid => params != null && errorMessage == null;
}

RunRequestValidation buildRunRequestParams({
  required String enteredInputFile,
  required String enteredOutputFile,
  required List<String> readNodeConfigInputFiles,
  required List<WriteNodeOption> writeNodes,
  String? preferredPrimaryWriteNodeId,
}) {
  final enteredInput = enteredInputFile.trim();
  final enteredOutput = enteredOutputFile.trim();

  final nonEmptyReadConfigInputs = readNodeConfigInputFiles
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  final inputFile = enteredInput.isNotEmpty
      ? enteredInput
      : (nonEmptyReadConfigInputs.length == 1
            ? nonEmptyReadConfigInputs.single
            : '');
  if (inputFile.isEmpty) {
    return const RunRequestValidation(errorMessage: 'input_file is required');
  }

  final primaryNodeId = choosePrimaryWriteNodeId(
    writes: writeNodes,
    preferredPrimaryNodeId: preferredPrimaryWriteNodeId,
  );
  final outputFile = enteredOutput.isNotEmpty
      ? enteredOutput
      : (chooseRunOutputFile(
              writes: writeNodes,
              primaryNodeId: preferredPrimaryWriteNodeId,
            ) ??
            '');

  if (outputFile.isEmpty) {
    if (writeNodes.length > 1 &&
        primaryNodeId == null &&
        enteredOutput.isEmpty) {
      return const RunRequestValidation(
        errorMessage:
            'Select a primary output node and set output_file, or enter output_file in Run Panel.',
        needsPrimarySelection: true,
      );
    }
    return const RunRequestValidation(errorMessage: 'output_file is required');
  }

  return RunRequestValidation(
    params: RunRequestParams(
      inputFile: inputFile,
      outputFile: outputFile,
      primaryWriteNodeId: primaryNodeId ?? '',
    ),
  );
}
