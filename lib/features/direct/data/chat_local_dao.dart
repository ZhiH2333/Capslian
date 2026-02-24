import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models/message_model.dart';

/// 本地 SQLite 消息缓存，用于离线与首屏加速。
class ChatLocalDao {
  ChatLocalDao._();
  static Database? _db;
  static const String _table = 'chat_messages';

  static Future<Database> _getDb() async {
    if (_db != null && (_db!.isOpen)) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'molian_chat.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id TEXT PRIMARY KEY,
            sender_id TEXT NOT NULL,
            receiver_id TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT,
            read INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_chat_messages_peer ON $_table (sender_id, receiver_id)',
        );
      },
    );
    return _db!;
  }

  /// 插入或替换单条（与 API 字段一致：sender_id, receiver_id, content, created_at, read）。
  static Future<void> insertOrReplace(Map<String, dynamic> row) async {
    final db = await _getDb();
    await db.insert(
      _table,
      <String, dynamic>{
        'id': row['id'],
        'sender_id': row['sender_id'],
        'receiver_id': row['receiver_id'],
        'content': row['content'] ?? '',
        'created_at': row['created_at'],
        'read': (row['read'] == true || row['read'] == 1) ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量插入或替换。
  static Future<void> insertOrReplaceAll(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final db = await _getDb();
    final batch = db.batch();
    for (final row in rows) {
      batch.insert(
        _table,
        <String, dynamic>{
          'id': row['id'],
          'sender_id': row['sender_id'],
          'receiver_id': row['receiver_id'],
          'content': row['content'] ?? '',
          'created_at': row['created_at'],
          'read': (row['read'] == true || row['read'] == 1) ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 获取与某用户的聊天记录（与 myId/peerId 顺序无关），按 created_at 升序，支持分页。
  /// [beforeCreatedAt] 为 null 时取最新 [limit] 条；否则取 created_at < beforeCreatedAt 的 [limit] 条。
  static Future<List<MessageModel>> getMessages({
    required String myId,
    required String peerId,
    int limit = 50,
    String? beforeCreatedAt,
  }) async {
    final db = await _getDb();
    final where = '(sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)';
    final args = <dynamic>[myId, peerId, peerId, myId];
    String orderBy = 'created_at DESC';
    if (beforeCreatedAt != null) {
      args.add(beforeCreatedAt);
      final rows = await db.query(
        _table,
        where: '$where AND created_at < ?',
        whereArgs: args,
        orderBy: orderBy,
        limit: limit,
      );
      final list = rows.map((r) => _rowToMessage(r)).toList();
      list.sort((a, b) => _compareCreatedAt(a.createdAt, b.createdAt));
      return list;
    }
    final rows = await db.query(
      _table,
      where: where,
      whereArgs: args,
      orderBy: orderBy,
      limit: limit,
    );
    final list = rows.map((r) => _rowToMessage(r)).toList();
    list.sort((a, b) => _compareCreatedAt(a.createdAt, b.createdAt));
    return list;
  }

  static MessageModel _rowToMessage(Map<String, dynamic> r) {
    return MessageModel.fromJson(<String, dynamic>{
      'id': r['id'],
      'sender_id': r['sender_id'],
      'receiver_id': r['receiver_id'],
      'content': r['content'],
      'created_at': r['created_at'],
      'read': (r['read'] as int?) == 1,
    });
  }

  /// 与 chat_providers 一致：时间升序（早→晚），createdAt 为 null 的乐观消息排末尾。
  static int _compareCreatedAt(String? a, String? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }
}
