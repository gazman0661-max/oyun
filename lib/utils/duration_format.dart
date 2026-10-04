/// Bir [Duration]'ı "1s 23dk" ya da "07:42" gibi kısa, okunur bir
/// geri sayım metnine çevirir. Enerji dolum sayacı ve reklam kilidi
/// sayacı için ortak kullanılır.
String formatCountdown(Duration d) {
  final total = d.inSeconds.clamp(0, 1 << 30);
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  if (hours > 0) {
    return '${hours}s ${minutes}dk';
  }
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return '$mm:$ss';
}
