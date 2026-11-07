# Changelog

## 2.0.0

### Breaking
- `count_words` is renamed `word_count`.
- `strip_tags` moved to `textkit.html`.
- `slugify`: the default separator is now `"_"` (was `"-"`), following the new style guide.
  Pass `sep="-"` to keep the old slugs.
- `truncate(text, width)`: `width` now counts the ellipsis, so the result is never longer than
  `width`. Callers that want the old output should pass `width + 1`.
- Python 3.8 is no longer supported.

### New
- `truncate` takes `on_word=True` to cut at the last space.

### Fixed
- `truncate` no longer fails when `width` is smaller than the ellipsis.

## 1.4.2
- Fixed: `strip_tags` collapses newlines too.

## 1.4.0
- New: `count_words`.

## 1.3.0
- New: `truncate` takes an `ellipsis` argument.
