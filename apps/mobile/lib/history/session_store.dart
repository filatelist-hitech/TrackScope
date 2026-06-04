// Session persistence via SharedPreferences.
//
// Хранит список сессий как JSON-массив под ключом 'bpm_sessions_v1'.
// Операции: load, save. Синхронны по модели (async I/O скрыт внутри).

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'session.dart';

const _kKey = 'bpm_sessions_v1';
const _kMaxSessions = 100;

class SessionStore {
  static Future<List<Session>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Session.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Session> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final capped = sessions.length > _kMaxSessions
        ? sessions.sublist(sessions.length - _kMaxSessions)
        : sessions;
    await prefs.setString(_kKey, jsonEncode(capped.map((s) => s.toJson()).toList()));
  }
}
