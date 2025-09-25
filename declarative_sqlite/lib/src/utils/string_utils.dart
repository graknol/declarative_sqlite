bool isNullOrWhitespace(String? value) {
  if (value == null) {
    return true;
  }
  if (value.trim().isEmpty) {
    return true;
  }
  return false;
}