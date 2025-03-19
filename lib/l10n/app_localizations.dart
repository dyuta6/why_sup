import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('tr'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String get invalidPhoneFormat =>
      'Lütfen ülke kodu ile birlikte geçerli bir telefon numarası girin (örn: +1...)';
  String get phoneNumberHelper =>
      'Lütfen ülke kodu ile birlikte telefon numaranızı girin';
  String get phoneNumberHint => '+XX XXX XXX XX XX';
  String get phoneEmptyError => 'Lütfen telefon numaranızı girin';
  String get loginFailedError => 'Giriş başarısız oldu';
  String get genericError => 'Bir hata oluştu';
  String get verificationIdMissingError => 'Doğrulama kodu eksik';
  String get smsEmptyError => 'Lütfen SMS kodunu girin';
  String get invalidSmsCodeError => 'Geçersiz SMS kodu';
  String get invalidVerificationIdError => 'Geçersiz doğrulama kodu';
  String get networkError => 'Ağ bağlantısı hatası';
  String get anonymousLoginDisabledError => 'Anonim giriş devre dışı';
  String get smsDialogTitle => 'SMS Doğrulama';
  String get smsCodeLabel => 'SMS Kodu';
  String get cancelButton => 'İptal';
  String get verifyButton => 'Doğrula';
  String get appTitle => 'WhySup';
  String get phoneLoginTitle => 'Telefon ile Giriş';
  String get phoneNumberLabel => 'Telefon Numarası';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['tr', 'en'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
