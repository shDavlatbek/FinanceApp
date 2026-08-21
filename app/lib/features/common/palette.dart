/// The colour and emoji vocabulary the category and account editors share.
///
/// Both editors offer the same swatches on purpose: a savings account tinted
/// the same green as the Groceries category is what makes the two lists read
/// as one product rather than two screens that happen to be in one app.
library;

/// The 11 distinct colours used by the seed categories and accounts in
/// docs/ARCHITECTURE.md. Category bars, donut slices, chips and account
/// medallions all draw from this list and nothing else.
const List<String> kSeedPalette = <String>[
  '#4CAF7D',
  '#E8935A',
  '#5A9BE8',
  '#9B7DE8',
  '#E8C95A',
  '#E85A7A',
  '#D45AE8',
  '#5AE8D4',
  '#7A8BE8',
  '#5AC8E8',
  '#8E8E93',
];

/// Emoji offered when naming a category.
const List<String> kCategoryEmojiSuggestions = <String>[
  '🛒', '☕', '🚕', '🏠', '💡', '💊', '🛍️', '🎮', '📱', '✈️', '📦',
  '💼', '💻', '🎁', '➕', '🍔', '🍕', '🍺', '🎬', '🎵', '📚', '🐾',
  '👶', '💪', '🚗', '⛽', '🎨', '⚽', '🧾', '💳', '🎓', '🌐',
];

/// Emoji offered when naming an account — places money sits, not things it is
/// spent on, so this is a different list rather than the same one reused.
const List<String> kAccountEmojiSuggestions = <String>[
  '💵', '💳', '🏦', '📈', '👛', '💰', '🪙', '💶', '💴', '💷', '🧧',
  '🏧', '📊', '🥇', '🏘️', '🚗', '🎯', '🔒', '🧮', '📉', '🐷', '🎁',
];
