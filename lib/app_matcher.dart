import 'sound_table.dart';
import 'voice_command.dart';

/// An app on the phone that can be opened from its home screen.
class InstalledApp {
  const InstalledApp({required this.label, required this.package});

  /// The name under its icon.
  final String label;
  final String package;
}

/// The installed app a spoken name most likely means, or null.
///
/// With [sounds], a name that fits no app as written is matched by how it
/// sounds: "瞎皮" opens 蝦皮購物.
InstalledApp? matchApp(
  String spoken,
  Iterable<InstalledApp> apps, {
  SoundTable? sounds,
}) {
  final asked = normalizeTranscript(spoken);
  if (asked.isEmpty) return null;
  // Everything the spoken name may be called on a home screen.
  final names = {
    asked,
    for (final group in _sameApp)
      if (group.contains(asked)) ...group,
  };
  InstalledApp? best;
  var bestScore = 0;
  for (final app in apps) {
    final label = normalizeTranscript(app.label);
    if (label.isEmpty) continue;
    var score = 0;
    for (final name in names) {
      // The word that was said counts for more than another name for it.
      final exact = name == asked ? 100 : 70;
      final fit = label == name
          ? exact
          : name.length >= 2 && label.contains(name)
          ? exact - 15
          : label.length >= 2 && name.contains(label)
          ? exact - 25
          : 0;
      if (fit > score) score = fit;
    }
    final shorter =
        score == bestScore &&
        best != null &&
        app.label.length < best.label.length;
    if (score > bestScore || (score > 0 && shorter)) {
      best = app;
      bestScore = score;
    }
  }
  if (best != null || sounds == null) return best;

  // No app is called that, so go by sound: "瞎皮" is 蝦皮, and "象機" is
  // 相機, which this phone may call 照相機.
  final alike = {asked: 0};
  for (final group in _sameApp) {
    if (!group.any((name) => sounds.alike(asked, name) != null)) continue;
    for (final name in group) {
      // As above, the word that was said counts for more than another name
      // for it.
      alike.putIfAbsent(name, () => sounds.alike(asked, name) ?? 3 * _kind);
    }
  }
  int? least;
  for (final app in apps) {
    final label = normalizeTranscript(app.label);
    for (final MapEntry(key: name, value: penalty) in alike.entries) {
      final distance = _soundDistance(name, label, sounds);
      if (distance == null) continue;
      final shorter =
          distance + penalty == least &&
          best != null &&
          app.label.length < best.label.length;
      if (least == null || distance + penalty < least || shorter) {
        best = app;
        least = distance + penalty;
      }
    }
  }
  return best;
}

/// Each kind of match by sound is this much further off than the one
/// before, whatever the sounds cost.
const _kind = 1000;

/// How far a spoken [name] is from an app's [label] by sound, or null when
/// they are not alike: least for the whole label, then for a label that
/// has the name in it, then for a name that has the label in it.
int? _soundDistance(String name, String label, SoundTable sounds) {
  final whole = sounds.alike(name, label);
  if (whole != null) return whole;
  if (name.length >= 2 && name.length < label.length) {
    final cost = sounds.within(name, label);
    if (cost != null) return _kind + cost;
  }
  if (label.length >= 2 && label.length < name.length) {
    final cost = sounds.within(label, name);
    if (cost != null) return 2 * _kind + cost;
  }
  return null;
}

/// Names that mean the same app. Phone makers label their own apps
/// differently ("相簿", "圖庫", "媒體瀏覽器").
const _sameApp = [
  {'相機', '照相機', 'camera'},
  {'相簿', '相片', '照片', '圖庫', '圖片庫', '媒體瀏覽器', 'photos', 'gallery'},
  {'時鐘', '鬧鐘', 'clock'},
  {'計算機', '計算器', 'calculator'},
  {'行事曆', '日曆', 'calendar'},
  {'設定', 'settings'},
  {'電話', '撥號', 'phone'},
  {'聯絡人', '通訊錄', 'contacts'},
  {'瀏覽器', '網際網路', '上網', 'chrome', 'internet'},
  {'信箱', '郵件', '電子郵件', 'gmail', 'mail'},
  {'蝦皮', '蝦皮購物', 'shopee'},
  {'ig', 'instagram'},
  {'賴', 'line'},
  {'臉書', 'facebook'},
  {'地圖', 'maps', 'google地圖'},
  {'play商店', '商店', 'playstore', 'googleplay商店'},
];
