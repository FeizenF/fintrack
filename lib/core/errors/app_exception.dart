/// Errors raised by the data layer that the UI is expected to handle.
///
/// Every message here is already user-facing Indonesian text: the presentation
/// layer shows [message] directly and never inspects database internals.
sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Input failed a business rule (blank name, zero amount, mismatched category).
class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// The requested row does not exist (or was removed concurrently).
class NotFoundException extends AppException {
  const NotFoundException(super.message);
}

/// The change would break ledger integrity, e.g. deleting a used account.
class ConflictException extends AppException {
  const ConflictException(super.message);
}
