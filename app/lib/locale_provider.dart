import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale;

  LocaleProvider(this._locale);

  Locale get locale => _locale;

  bool get isEnglish => _locale.languageCode == 'en';

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', locale.languageCode);
    notifyListeners();
  }

  void setEnglish() => setLocale(const Locale('en'));
  void setSpanish() => setLocale(const Locale('es'));
}

class LocaleProviderScope extends InheritedNotifier<LocaleProvider> {
  const LocaleProviderScope({super.key, required LocaleProvider notifier, required super.child}) : super(notifier: notifier);

  static LocaleProvider of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleProviderScope>();
    if (scope == null) {
      throw FlutterError(
        'LocaleProviderScope.of() called with a context that does not contain a LocaleProviderScope.',
      );
    }
    return scope.notifier!;
  }
}
