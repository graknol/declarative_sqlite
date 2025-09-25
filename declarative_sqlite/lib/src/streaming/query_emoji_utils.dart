/// Animal emojis for query ID differentiation
const animalEmojis = [
  '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
  '🦁', '🐮', '🐷', '🐸', '🐵', '🙈', '🙉', '🙊', '🐒', '🐔',
  '🐧', '🐦', '🐤', '🐣', '🐥', '🦆', '🦅', '🦉', '🦇', '🐺',
  '🐗', '🐴', '🦄', '🐝', '🐛', '🦋', '🐌', '🐞', '🐜', '🦟',
  '🦗', '🕷️', '🦂', '🐢', '🐍', '🦎', '🦖', '🦕', '🐙', '🦑',
  '🦐', '🦞', '🦀', '🐡', '🐠', '🐟', '🐬', '🐳', '🐋', '🦈',
  '🐊', '🐅', '🐆', '🦓', '🦏', '🦛', '🐘', '🦒', '🦘', '🐿️',
  '🦔', '🦇', '🐁', '🐀', '🐈', '🐕', '🐩', '🐂', '🐄', '🐎',
  '🐖', '🐏', '🐑', '🦙', '🐐', '🦌', '🐕‍🦺', '🐈‍⬛', '🐓', '🦃',
  '🦚', '🦜', '🦢', '🦩', '🕊️', '🐇', '🦝', '🦨', '🦡', '🦫'
];

/// Generate an animal emoji based on query ID hash
String getAnimalEmoji(String queryId) {
  final hash = queryId.hashCode.abs();
  return animalEmojis[hash % animalEmojis.length];
}