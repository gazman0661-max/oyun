package com.astrofelyx.pro

import com.google.android.gms.games.PlayGames
import com.google.android.gms.games.SnapshotsClient
import com.google.android.gms.games.leaderboard.LeaderboardVariant
import com.google.android.gms.games.snapshot.SnapshotMetadataChange
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.Charset

/// Flutter <-> Play Games Services v2 (giris + Saved Games/Snapshot
/// bulut kaydi + skor tablosu) arasindaki kucuk kopru.
///
/// NOT: Bu dosya derlenip test edilmedi (bu ortamda Android SDK/emulator
/// yok) — flutlab.io gibi tarayici tabanli bir onizlemede DE calismaz,
/// gercek bir Android derlemesi/cihazi gerekir. `flutter build apk`
/// sirasinda bir API uyusmazligi cikarsa, hata mesajindaki metod/sinif
/// adini "Play Games Services v2 Leaderboards" arayarak Google'in guncel
/// dokumantasyonuyla karsilastir; yapi ayni kalir, isimler ufak
/// degisebilir.
class MainActivity : FlutterActivity() {
    private val channelName = "space_sort/play_games"
    // Play Console'da olusturdugun oyunun ID'siyle karismamasi icin
    // sabit, aciklayici bir Snapshot adi.
    private val snapshotName = "space_sort_progress"

    // ONEMLI: Play Console > "Play Games Services" > "Skor Tabloları"
    // bolumunden olusturacagin skor tablosunun GERCEK ID'si ile
    // degistir; degistirmeden skor gonderme/goruntuleme CALISMAZ.
    // bkz. README_PLAY_GAMES.md
    private val leaderboardId = "CgkIpvOV150JEAIQAQ"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "signInSilently" -> signIn(result, silentOnly = true)
                    "signIn" -> signIn(result, silentOnly = false)
                    "saveProgress" -> {
                        val data = call.argument<String>("data") ?: ""
                        saveProgress(data, result)
                    }
                    "loadProgress" -> loadProgress(result)
                    "submitScore" -> {
                        val score = call.argument<Int>("score") ?: 0
                        submitScore(score, result)
                    }
                    "showLeaderboard" -> showLeaderboard(result)
                    "submitBoardScore" -> {
                        val boardId = call.argument<String>("boardId") ?: ""
                        val score = call.argument<Number>("score")?.toLong() ?: 0L
                        val tag = call.argument<String>("tag") ?: ""
                        submitBoardScore(boardId, score, tag, result)
                    }
                    "loadLeaderboard" -> {
                        val boardId = call.argument<String>("boardId") ?: ""
                        val span = call.argument<Int>("span") ?: LeaderboardVariant.TIME_SPAN_ALL_TIME
                        loadLeaderboard(boardId, span, result)
                    }
                    "loadMyLeaderboardScore" -> {
                        val boardId = call.argument<String>("boardId") ?: ""
                        val span = call.argument<Int>("span") ?: LeaderboardVariant.TIME_SPAN_ALL_TIME
                        loadMyLeaderboardScore(boardId, span, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun signIn(result: MethodChannel.Result, silentOnly: Boolean) {
        val signInClient = PlayGames.getGamesSignInClient(this)
        signInClient.isAuthenticated.addOnCompleteListener { task ->
            val alreadyAuthenticated = task.isSuccessful && task.result.isAuthenticated
            if (alreadyAuthenticated) {
                result.success(true)
                return@addOnCompleteListener
            }
            if (silentOnly) {
                // Sessiz modda: kullaniciya hicbir UI gostermeden birak,
                // sadece "baglı degil" sonucunu don.
                result.success(false)
                return@addOnCompleteListener
            }
            // Kullanici bizzat "Bağlan" butonuna bastı: Google'in giris
            // akisini goster.
            signInClient.signIn().addOnCompleteListener { signInTask ->
                val ok = signInTask.isSuccessful && signInTask.result.isAuthenticated
                result.success(ok)
            }
        }
    }

    private fun saveProgress(data: String, result: MethodChannel.Result) {
        val snapshotsClient = PlayGames.getSnapshotsClient(this)
        snapshotsClient
            .open(snapshotName, true, SnapshotsClient.RESOLUTION_POLICY_LONGEST_PLAYTIME)
            .addOnCompleteListener { task ->
                val snapshot = task.result?.data
                if (!task.isSuccessful || snapshot == null) {
                    result.success(false)
                    return@addOnCompleteListener
                }
                try {
                    snapshot.snapshotContents.writeBytes(data.toByteArray(Charset.forName("UTF-8")))
                    val metadataChange = SnapshotMetadataChange.Builder()
                        .setDescription("AstroFelyx - oyuncu ilerlemesi")
                        .build()
                    snapshotsClient.commitAndClose(snapshot, metadataChange)
                        .addOnCompleteListener { commitTask ->
                            result.success(commitTask.isSuccessful)
                        }
                } catch (e: Exception) {
                    result.success(false)
                }
            }
    }

    private fun loadProgress(result: MethodChannel.Result) {
        val snapshotsClient = PlayGames.getSnapshotsClient(this)
        snapshotsClient
            .open(snapshotName, true, SnapshotsClient.RESOLUTION_POLICY_LONGEST_PLAYTIME)
            .addOnCompleteListener { task ->
                val snapshot = task.result?.data
                if (!task.isSuccessful || snapshot == null) {
                    result.success(null)
                    return@addOnCompleteListener
                }
                try {
                    val bytes = snapshot.snapshotContents.readFully()
                    snapshotsClient.discardAndClose(snapshot)
                    val text = if (bytes == null) "" else String(bytes, Charset.forName("UTF-8"))
                    result.success(if (text.isEmpty()) null else text)
                } catch (e: Exception) {
                    result.success(null)
                }
            }
    }

    /// [score] tek bir sayidir (PlayerProgress.totalScore, kumulatif
    /// toplam skor). Play Games SDK'si bunu ayni anda GUNLUK, HAFTALIK
    /// ve TUM-ZAMANLAR skor tablolarinin ucune de otomatik isler — ayri
    /// ayri gondermemize gerek yok, tek cagri yeterli.
    private fun submitScore(score: Int, result: MethodChannel.Result) {
        try {
            val leaderboardsClient = PlayGames.getLeaderboardsClient(this)
            leaderboardsClient.submitScore(leaderboardId, score.toLong())
            // submitScore firlatip-unut (fire-and-forget) bir cagridir;
            // Google sunucu tarafinda kuyruklar. Cagrinin kendisi
            // (yerel olarak) basarili tetiklendiyse true donuyoruz.
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    /// Google'in kendi skor tablosu ekranini (Gunluk/Haftalik/Tum-
    /// zamanlar sekmeleriyle) oyunun uzerine acar.
    private fun showLeaderboard(result: MethodChannel.Result) {
        val leaderboardsClient = PlayGames.getLeaderboardsClient(this)
        leaderboardsClient.getLeaderboardIntent(leaderboardId)
            .addOnSuccessListener { intent ->
                startActivityForResult(intent, 9004)
                result.success(true)
            }
            .addOnFailureListener {
                result.success(false)
            }
    }

    /// Ozel skor tablosu (Dunya / Turkiye "en iyi oyun skoru"): [boardId]
    /// tablosuna [score] gonderir. [tag] (URI-guvenli, en fazla 64 karakter)
    /// oyuncunun rutbe seviyesini tasir (orn. "l12"); listeyi cekerken
    /// ayni etiket geri okunur.
    private fun submitBoardScore(
        boardId: String,
        score: Long,
        tag: String,
        result: MethodChannel.Result
    ) {
        try {
            if (boardId.isEmpty()) {
                result.success(false)
                return
            }
            val leaderboardsClient = PlayGames.getLeaderboardsClient(this)
            leaderboardsClient.submitScore(boardId, score, tag)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    /// [boardId] tablosunun HERKESE ACIK ilk 25 skorunu [span] icin
    /// (0 gunluk, 1 haftalik, 2 tum zamanlar) dondurur. Hata olursa null.
    private fun loadLeaderboard(boardId: String, span: Int, result: MethodChannel.Result) {
        try {
            val client = PlayGames.getLeaderboardsClient(this)
            client.loadTopScores(boardId, span, LeaderboardVariant.COLLECTION_PUBLIC, 25)
                .addOnSuccessListener { annotated ->
                    val data = annotated.get()
                    if (data == null) {
                        result.success(ArrayList<Map<String, Any?>>())
                        return@addOnSuccessListener
                    }
                    val buffer = data.scores
                    val list = ArrayList<Map<String, Any?>>()
                    for (i in 0 until buffer.count) {
                        val s = buffer.get(i)
                        list.add(
                            mapOf(
                                "rank" to s.rank,
                                "score" to s.rawScore,
                                "name" to s.scoreHolderDisplayName,
                                "tag" to s.scoreTag
                            )
                        )
                    }
                    data.release()
                    result.success(list)
                }
                .addOnFailureListener { result.success(null) }
        } catch (e: Exception) {
            result.success(null)
        }
    }

    /// Oyuncunun KENDI skoru ve sirasi ([span] icin). Skoru yoksa null.
    private fun loadMyLeaderboardScore(boardId: String, span: Int, result: MethodChannel.Result) {
        try {
            val client = PlayGames.getLeaderboardsClient(this)
            client.loadCurrentPlayerLeaderboardScore(
                boardId, span, LeaderboardVariant.COLLECTION_PUBLIC
            )
                .addOnSuccessListener { annotated ->
                    val s = annotated.get()
                    if (s == null) {
                        result.success(null)
                    } else {
                        result.success(
                            mapOf(
                                "rank" to s.rank,
                                "score" to s.rawScore,
                                "name" to s.scoreHolderDisplayName,
                                "tag" to s.scoreTag
                            )
                        )
                    }
                }
                .addOnFailureListener { result.success(null) }
        } catch (e: Exception) {
            result.success(null)
        }
    }
}
