import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../widgets/ui_kit.dart';

enum LegalKind { terms, privacy }

/// Kullanim Sartlari / Gizlilik Politikasi metin ekrani.
///
/// DIKKAT: Asagidaki metinler TASLAKTIR. Magazaya cikmadan once gercek
/// metinlerle (ya da yayinladigin web sayfasinin baglantisiyla) degistir:
/// Google Play, gizlilik politikasi baglantisi ZORUNLU tutuyor. Reklam ve
/// uygulama ici satin alma gercek hale gelince metni ona gore guncelle.
class LegalScreen extends StatelessWidget {
  final LegalKind kind;
  const LegalScreen({super.key, required this.kind});

  static const String _termsTr = '''
KULLANIM ŞARTLARI (TASLAK)

1. Genel
Merge Worlds oyununu indirerek veya oynayarak bu şartları kabul etmiş olursun.

2. Lisans
Oyunu kişisel ve ticari olmayan amaçla oynayabilirsin. Oyunun kodunu, görsellerini veya seslerini izinsiz kopyalayamaz, dağıtamaz veya değiştiremezsin.

3. Sanal ürünler
Oyundaki coin, elmas ve enerji gibi sanal ürünlerin gerçek para değeri yoktur. Satın alınan sanal ürünler iade edilmez; mağaza iade kuralları saklıdır.

4. Hesap ve ilerleme
İlerlemen cihazında saklanır. Uygulamayı silmen veya cihazını değiştirmen ilerlemeni kaybettirebilir.

5. Davranış
Oyunu hile, otomasyon veya kötüye kullanım amacıyla kullanamazsın.

6. Değişiklikler
Bu şartlar zaman zaman güncellenebilir. Güncel hâli oyundan erişilebilir.

7. İletişim
[iletişim e-postası buraya yazılacak]
''';

  static const String _termsEn = '''
TERMS OF USE (DRAFT)

1. General
By downloading or playing Merge Worlds you agree to these terms.

2. License
You may play the game for personal, non-commercial use. You may not copy, distribute or modify the game's code, art or audio without permission.

3. Virtual items
Coins, gems, energy and other virtual items have no real-world value. Purchased virtual items are non-refundable, subject to your app store's refund rules.

4. Account and progress
Your progress is stored on your device. Uninstalling the app or changing devices may lose your progress.

5. Conduct
You may not use cheats, automation or abuse the game.

6. Changes
These terms may be updated from time to time. The current version is available in the game.

7. Contact
[contact e-mail to be added here]
''';

  static const String _privacyTr = '''
GİZLİLİK POLİTİKASI (TASLAK)

1. Topladığımız veriler
Oyun ilerlemen (bölüm, coin, elmas, ayarlar) cihazında yerel olarak saklanır. Şu an kişisel kimlik bilgisi toplamıyoruz.

2. Reklamlar
Oyun ödüllü ve geçiş reklamları gösterir. Reklamlar Appodeal ve reklam ortakları aracılığıyla sunulur; bu ortaklar reklam göstermek, ölçümlemek ve dolandırıcılığı önlemek için cihaz reklam kimliği, yaklaşık konum ve cihaz bilgisi gibi verileri kendi politikalarına göre işleyebilir. AB/AEA, Birleşik Krallık ve ilgili bölgelerde reklam rızanı ilk açılışta soruyoruz; tercihini istediğin zaman Seçenekler > Reklam Rızasını Yönet bölümünden değiştirebilirsin. Cihaz ayarlarından reklam kimliğini sıfırlayabilir veya kişiselleştirmeyi kapatabilirsin.

3. Satın almalar
Uygulama içi satın almalar Google Play veya App Store üzerinden işlenir. Ödeme bilgilerine erişemeyiz.

4. Bildirimler
İzin verirsen enerji, görev ve inşaat bildirimleri gönderebiliriz. İzni cihaz ayarlarından kapatabilirsin.

5. Çocuklar
Oyun 13 yaş altı çocuklara bilerek kişisel veri toplamaz.

6. Haklarınız
Verilerinle ilgili sorularını aşağıdaki adrese iletebilirsin.

7. İletişim
[iletişim e-postası buraya yazılacak]
''';

  static const String _privacyEn = '''
PRIVACY POLICY (DRAFT)

1. Data we collect
Your game progress (chapters, coins, gems, settings) is stored locally on your device. We do not currently collect personal identifiers.

2. Ads
The game shows rewarded and interstitial ads. Ads are served through Appodeal and its ad partners, who may process data such as the device advertising ID, approximate location and device information to serve and measure ads and prevent fraud, according to their own policies. In the EEA, the UK and other applicable regions we ask for your ad consent on first launch; you can change your choice at any time in Settings > Manage Ad Consent. You can also reset your advertising ID or turn off personalization in your device settings.

3. Purchases
In-app purchases are processed by Google Play or the App Store. We cannot access your payment details.

4. Notifications
If you allow it, we may send energy, mission and construction notifications. You can turn them off in your device settings.

5. Children
The game does not knowingly collect personal data from children under 13.

6. Your rights
You can send questions about your data to the address below.

7. Contact
[contact e-mail to be added here]
''';

  @override
  Widget build(BuildContext context) {
    final tr = AppStrings.instance.language == AppLanguage.tr;
    final isTerms = kind == LegalKind.terms;
    final title = isTerms ? (tr ? 'Kullanım Şartları' : 'Terms of Use') : (tr ? 'Gizlilik Politikası' : 'Privacy Policy');
    final text = isTerms ? (tr ? _termsTr : _termsEn) : (tr ? _privacyTr : _privacyEn);
    return GameScaffold(
      title: title,
      showCurrency: false,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 40),
        child: Text(
          text.trim(),
          style: const TextStyle(fontSize: 15, height: 1.35, color: Color(0xFF4A2C0A), fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
