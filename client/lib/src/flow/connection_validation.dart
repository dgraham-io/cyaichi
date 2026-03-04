class TypedConnectionValidation {
  const TypedConnectionValidation._({required this.allowed, this.reason});

  final bool allowed;
  final String? reason;

  const TypedConnectionValidation.allow() : this._(allowed: true);

  const TypedConnectionValidation.deny(String reason)
    : this._(allowed: false, reason: reason);
}

TypedConnectionValidation validateTypedConnection({
  required bool sourceIsOutput,
  required bool targetIsInput,
  String? sourceSchema,
  String? targetSchema,
}) {
  if (!sourceIsOutput || !targetIsInput) {
    return const TypedConnectionValidation.deny(
      'Connections must go from output ports to input ports.',
    );
  }

  final from = (sourceSchema ?? '').trim();
  final to = (targetSchema ?? '').trim();
  if (from.isNotEmpty && to.isNotEmpty && from != to) {
    return TypedConnectionValidation.deny('Port schema mismatch: $from -> $to');
  }

  return const TypedConnectionValidation.allow();
}
