import 'package:flutter_test/flutter_test.dart';
import 'package:fastfood_merge/services/save_merge.dart';

Stores _s(Map<String, dynamic> progress, {Map<String, dynamic>? piggy}) => {
      SaveMerge.kProgress: progress,
      if (piggy != null) SaveMerge.kPiggy: piggy,
    };

void main() {
  test('A harcar, B kazanir: ikisi de korunur (delta)', () {
    final base = _s({'gems': 100, 'coins': 500});
    final a = _s({'gems': 40, 'coins': 500}); // A 60 mucevher harcadi
    final cloudAfterB = _s({'gems': 130, 'coins': 500}); // B 30 kazandi, buluta yazdi
    final m = SaveMerge.all(base, a, cloudAfterB);
    expect(m[SaveMerge.kProgress]!['gems'], 70); // 130 - 60
  });

  test('eski cihaz bulutu ezmez: harcama negatife dusmez', () {
    final base = _s({'gems': 50});
    final local = _s({'gems': 0});
    final cloud = _s({'gems': 20});
    final m = SaveMerge.all(base, local, cloud);
    expect(m[SaveMerge.kProgress]!['gems'], 0);
  });

  test('tek seferlik satin alma ve seviyeler geri gitmez', () {
    final local = _s({'starterPackBought': true, 'maxUnlockedChapter': 3, 'townLevels': [2, 0]});
    final cloud = _s({'starterPackBought': false, 'maxUnlockedChapter': 5, 'townLevels': [1, 4]});
    final m = SaveMerge.all(null, local, cloud)[SaveMerge.kProgress]!;
    expect(m['starterPackBought'], true);
    expect(m['maxUnlockedChapter'], 5);
    expect(m['townLevels'], [2, 4]);
  });

  test('gunluk odul iki cihazda iki kez alinmaz', () {
    final day = '2026-10-04T00:00:00.000';
    final local = _s({'lastDailyRewardClaim': day, 'dailyStreak': 4});
    final cloud = _s({'lastDailyRewardClaim': '2026-10-03T00:00:00.000', 'dailyStreak': 3});
    final m = SaveMerge.all(null, local, cloud)[SaveMerge.kProgress]!;
    expect(m['lastDailyRewardClaim'], day);
    expect(m['dailyStreak'], 4);
  });

  test('ayni donemde alinmis gorev odulu geri acilmaz', () {
    final d = '2026-10-04T00:00:00.000';
    final local = _s({'missionsResetDate': d, 'missionMergeClaimed': false, 'missionMergeProgress': 3});
    final cloud = _s({'missionsResetDate': d, 'missionMergeClaimed': true, 'missionMergeProgress': 5});
    final m = SaveMerge.all(null, local, cloud)[SaveMerge.kProgress]!;
    expect(m['missionMergeClaimed'], true);
    expect(m['missionMergeProgress'], 5);
  });

  test('kumbara: A bosaltti, B eski dolu hali gonderse cift odul olmaz', () {
    final base = _s({'gems': 0}, piggy: {'gems': 30});
    final bLocal = _s({'gems': 0}, piggy: {'gems': 30}); // B degismedi
    final cloud = _s({'gems': 30}, piggy: {'gems': 0}); // A bosaltti
    final m = SaveMerge.all(base, bLocal, cloud);
    expect(m[SaveMerge.kPiggy]!['gems'], 0);
    expect(m[SaveMerge.kProgress]!['gems'], 30);
  });

  test('ses ayarlari cihaza ozel kalir', () {
    final local = _s({'soundEnabled': false});
    final cloud = _s({'soundEnabled': true});
    expect(SaveMerge.all(null, local, cloud)[SaveMerge.kProgress]!['soundEnabled'], false);
  });

  test('rebase: ag turunda yapilan harcama kaybolmaz', () {
    final m = {'gems': 100};
    final l1 = {'gems': 50};
    final l2 = {'gems': 30}; // arada 20 harcandi
    expect(SaveMerge.rebase(SaveMerge.kProgress, m, l1, l2)['gems'], 80);
  });
}
