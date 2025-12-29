import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _tokenToKey = <String, LogicalKeyboardKey>{
  // Letters
  'a': LogicalKeyboardKey.keyA,
  'b': LogicalKeyboardKey.keyB,
  'c': LogicalKeyboardKey.keyC,
  'd': LogicalKeyboardKey.keyD,
  'e': LogicalKeyboardKey.keyE,
  'f': LogicalKeyboardKey.keyF,
  'g': LogicalKeyboardKey.keyG,
  'h': LogicalKeyboardKey.keyH,
  'i': LogicalKeyboardKey.keyI,
  'j': LogicalKeyboardKey.keyJ,
  'k': LogicalKeyboardKey.keyK,
  'l': LogicalKeyboardKey.keyL,
  'm': LogicalKeyboardKey.keyM,
  'n': LogicalKeyboardKey.keyN,
  'o': LogicalKeyboardKey.keyO,
  'p': LogicalKeyboardKey.keyP,
  'q': LogicalKeyboardKey.keyQ,
  'r': LogicalKeyboardKey.keyR,
  's': LogicalKeyboardKey.keyS,
  't': LogicalKeyboardKey.keyT,
  'u': LogicalKeyboardKey.keyU,
  'v': LogicalKeyboardKey.keyV,
  'w': LogicalKeyboardKey.keyW,
  'x': LogicalKeyboardKey.keyX,
  'y': LogicalKeyboardKey.keyY,
  'z': LogicalKeyboardKey.keyZ,

  // Digits
  '0': LogicalKeyboardKey.digit0,
  '1': LogicalKeyboardKey.digit1,
  '2': LogicalKeyboardKey.digit2,
  '3': LogicalKeyboardKey.digit3,
  '4': LogicalKeyboardKey.digit4,
  '5': LogicalKeyboardKey.digit5,
  '6': LogicalKeyboardKey.digit6,
  '7': LogicalKeyboardKey.digit7,
  '8': LogicalKeyboardKey.digit8,
  '9': LogicalKeyboardKey.digit9,

  // Punctuation / common keys
  '/': LogicalKeyboardKey.slash,
  'slash': LogicalKeyboardKey.slash,
  '.': LogicalKeyboardKey.period,
  'period': LogicalKeyboardKey.period,
  ',': LogicalKeyboardKey.comma,
  'comma': LogicalKeyboardKey.comma,
  '-': LogicalKeyboardKey.minus,
  'minus': LogicalKeyboardKey.minus,
  '=': LogicalKeyboardKey.equal,
  'equal': LogicalKeyboardKey.equal,
  '[': LogicalKeyboardKey.bracketLeft,
  'bracketleft': LogicalKeyboardKey.bracketLeft,
  ']': LogicalKeyboardKey.bracketRight,
  'bracketright': LogicalKeyboardKey.bracketRight,
  '\\': LogicalKeyboardKey.backslash,
  'backslash': LogicalKeyboardKey.backslash,
  ';': LogicalKeyboardKey.semicolon,
  'semicolon': LogicalKeyboardKey.semicolon,
  '\'': LogicalKeyboardKey.quote,
  'quote': LogicalKeyboardKey.quote,

  // Named keys
  'space': LogicalKeyboardKey.space,
  'tab': LogicalKeyboardKey.tab,
  'enter': LogicalKeyboardKey.enter,
  'return': LogicalKeyboardKey.enter,
  'esc': LogicalKeyboardKey.escape,
  'escape': LogicalKeyboardKey.escape,
  'backspace': LogicalKeyboardKey.backspace,
};

final _keyToToken = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.keyA: 'a',
  LogicalKeyboardKey.keyB: 'b',
  LogicalKeyboardKey.keyC: 'c',
  LogicalKeyboardKey.keyD: 'd',
  LogicalKeyboardKey.keyE: 'e',
  LogicalKeyboardKey.keyF: 'f',
  LogicalKeyboardKey.keyG: 'g',
  LogicalKeyboardKey.keyH: 'h',
  LogicalKeyboardKey.keyI: 'i',
  LogicalKeyboardKey.keyJ: 'j',
  LogicalKeyboardKey.keyK: 'k',
  LogicalKeyboardKey.keyL: 'l',
  LogicalKeyboardKey.keyM: 'm',
  LogicalKeyboardKey.keyN: 'n',
  LogicalKeyboardKey.keyO: 'o',
  LogicalKeyboardKey.keyP: 'p',
  LogicalKeyboardKey.keyQ: 'q',
  LogicalKeyboardKey.keyR: 'r',
  LogicalKeyboardKey.keyS: 's',
  LogicalKeyboardKey.keyT: 't',
  LogicalKeyboardKey.keyU: 'u',
  LogicalKeyboardKey.keyV: 'v',
  LogicalKeyboardKey.keyW: 'w',
  LogicalKeyboardKey.keyX: 'x',
  LogicalKeyboardKey.keyY: 'y',
  LogicalKeyboardKey.keyZ: 'z',
  LogicalKeyboardKey.digit0: '0',
  LogicalKeyboardKey.digit1: '1',
  LogicalKeyboardKey.digit2: '2',
  LogicalKeyboardKey.digit3: '3',
  LogicalKeyboardKey.digit4: '4',
  LogicalKeyboardKey.digit5: '5',
  LogicalKeyboardKey.digit6: '6',
  LogicalKeyboardKey.digit7: '7',
  LogicalKeyboardKey.digit8: '8',
  LogicalKeyboardKey.digit9: '9',
  LogicalKeyboardKey.slash: '/',
  LogicalKeyboardKey.period: '.',
  LogicalKeyboardKey.comma: ',',
  LogicalKeyboardKey.minus: '-',
  LogicalKeyboardKey.equal: '=',
  LogicalKeyboardKey.bracketLeft: '[',
  LogicalKeyboardKey.bracketRight: ']',
  LogicalKeyboardKey.backslash: '\\',
  LogicalKeyboardKey.semicolon: ';',
  LogicalKeyboardKey.quote: "'",
  LogicalKeyboardKey.space: 'space',
  LogicalKeyboardKey.tab: 'tab',
  LogicalKeyboardKey.enter: 'enter',
  LogicalKeyboardKey.escape: 'esc',
  LogicalKeyboardKey.backspace: 'backspace',
};

final _modifierKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
};

bool _isModifierKey(LogicalKeyboardKey key) => _modifierKeys.contains(key);

LogicalKeyboardKey? logicalKeyForToken(String token) {
  final normalized = token.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  return _tokenToKey[normalized];
}

String? tokenForLogicalKey(LogicalKeyboardKey key) {
  return _keyToToken[key];
}

SingleActivator? parseShortcutActivator(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final normalized = trimmed.toLowerCase().replaceAll(' ', '');
  final parts = normalized.split('+').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return null;

  var control = false;
  var alt = false;
  var shift = false;
  var meta = false;
  String? keyToken;

  for (final part in parts) {
    switch (part) {
      case 'ctrl':
      case 'control':
        control = true;
        continue;
      case 'alt':
        alt = true;
        continue;
      case 'shift':
        shift = true;
        continue;
      case 'cmd':
      case 'command':
      case 'meta':
      case 'win':
      case 'windows':
        meta = true;
        continue;
      default:
        if (keyToken != null) return null;
        keyToken = part;
    }
  }

  if (keyToken == null) return null;
  final key = logicalKeyForToken(keyToken);
  if (key == null) return null;
  return SingleActivator(
    key,
    control: control,
    alt: alt,
    shift: shift,
    meta: meta,
  );
}

String shortcutStringFromActivator(SingleActivator activator) {
  final parts = <String>[];
  if (activator.control) parts.add('ctrl');
  if (activator.alt) parts.add('alt');
  if (activator.shift) parts.add('shift');
  if (activator.meta) parts.add('meta');
  parts.add(tokenForLogicalKey(activator.trigger) ?? activator.trigger.keyLabel);
  return parts.join('+');
}

String normalizeShortcutString(String raw) {
  final activator = parseShortcutActivator(raw);
  if (activator == null) return raw.trim();
  return shortcutStringFromActivator(activator);
}

String shortcutDisplayLabel(String raw) {
  final activator = parseShortcutActivator(raw);
  if (activator == null) return raw.trim().isEmpty ? '-' : raw.trim();
  final parts = <String>[];
  if (activator.control) parts.add('Ctrl');
  if (activator.alt) parts.add('Alt');
  if (activator.shift) parts.add('Shift');
  if (activator.meta) parts.add('Meta');

  final token = tokenForLogicalKey(activator.trigger) ?? activator.trigger.keyLabel;
  parts.add(token.length == 1 ? token.toUpperCase() : _titleCase(token));
  return parts.join('+');
}

String? shortcutStringFromKeyEvent(KeyEvent event) {
  if (event is! KeyDownEvent) return null;
  final key = event.logicalKey;
  if (_isModifierKey(key)) return null;
  final token = tokenForLogicalKey(key);
  if (token == null) return null;
  final activator = SingleActivator(
    key,
    control: HardwareKeyboard.instance.isControlPressed,
    alt: HardwareKeyboard.instance.isAltPressed,
    shift: HardwareKeyboard.instance.isShiftPressed,
    meta: HardwareKeyboard.instance.isMetaPressed,
  );
  return shortcutStringFromActivator(activator);
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  if (value.length == 1) return value.toUpperCase();
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
