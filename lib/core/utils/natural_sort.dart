/// 自然排序：让 "1, 2, 10" 按数值顺序排列，而不是字典序 "1, 10, 2"。
///
/// 用于章节、音频文件的文件名排序。零填充（001）与非填充（1）等价。
class NaturalSort {
  NaturalSort._();

  /// 比较两个字符串的自然顺序。
  /// 返回负数表示 a 在 b 前，正数表示 a 在 b 后，0 表示相等。
  static int compare(String a, String b) {
    final ia = _TokenIterator(a);
    final ib = _TokenIterator(b);

    while (ia.hasNext && ib.hasNext) {
      final ta = ia.next();
      final tb = ib.next();

      if (ta.isNumber && tb.isNumber) {
        // 两段都是数字：按数值比较
        final na = _toInt(ta.text);
        final nb = _toInt(tb.text);
        final cmp = na.compareTo(nb);
        if (cmp != 0) return cmp;
        // 数值相同但写法不同（如 01 vs 1）：短的在前，保持稳定
        if (ta.text.length != tb.text.length) {
          return ta.text.length.compareTo(tb.text.length);
        }
      } else if (ta.isNumber) {
        // 数字排在文字前
        return -1;
      } else if (tb.isNumber) {
        return 1;
      } else {
        // 两段都是文字：不区分大小写比较
        final cmp = ta.text.toLowerCase().compareTo(tb.text.toLowerCase());
        if (cmp != 0) return cmp;
      }
    }

    // 一个字符串是另一个的前缀：短的在前
    if (ia.hasNext) return 1;
    if (ib.hasNext) return -1;
    return 0;
  }

  /// 对字符串列表做自然排序（返回新列表）
  static List<String> sort(Iterable<String> items) {
    final list = items.toList();
    list.sort(compare);
    return list;
  }

  static int _toInt(String s) {
    // 超大数字用字符串长度兜底，避免溢出
    if (s.length > 18) return int.tryParse(s.substring(0, 18)) ?? 0;
    return int.tryParse(s) ?? 0;
  }
}

class _Token {
  final String text;
  final bool isNumber;
  const _Token(this.text, this.isNumber);
}

class _TokenIterator {
  final String s;
  int _pos = 0;
  bool _done = false;
  _Token? _pending;

  _TokenIterator(this.s);

  bool get hasNext => !_done || _pending != null;

  _Token next() {
    if (_pending != null) {
      final t = _pending!;
      _pending = null;
      return t;
    }
    if (_pos >= s.length) {
      _done = true;
      return const _Token('', false);
    }

    final code = s.codeUnitAt(_pos);
    final isDigit = code >= 48 && code <= 57;
    final start = _pos;

    if (isDigit) {
      while (_pos < s.length) {
        final c = s.codeUnitAt(_pos);
        if (c < 48 || c > 57) break;
        _pos++;
      }
    } else {
      while (_pos < s.length) {
        final c = s.codeUnitAt(_pos);
        final digit = c >= 48 && c <= 57;
        if (digit) break;
        _pos++;
      }
    }

    if (_pos >= s.length) _done = true;
    return _Token(s.substring(start, _pos), isDigit);
  }
}
