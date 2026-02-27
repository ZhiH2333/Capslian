-- IM 协议：聊天室与事件（与 scope/alias → channel_id 识别一致）
-- scope = 'global' 时 realm_id 为 NULL；否则 realm_id 为 realms.id（通过 slug 解析）

-- 频道表：channel_id 为整数主键，供 WebSocket 订阅与 REST 使用
CREATE TABLE IF NOT EXISTS im_channels (
  id INTEGER PRIMARY KEY,
  realm_id TEXT,
  alias TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL DEFAULT 'direct',
  description TEXT,
  avatar_url TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE(realm_id, alias),
  FOREIGN KEY (realm_id) REFERENCES realms(id)
);

CREATE INDEX IF NOT EXISTS idx_im_channels_realm_alias ON im_channels(realm_id, alias);

-- 频道成员表：account_id 即 users.id
CREATE TABLE IF NOT EXISTS im_channel_members (
  id TEXT PRIMARY KEY,
  channel_id INTEGER NOT NULL,
  account_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member',
  joined_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  UNIQUE(channel_id, account_id),
  FOREIGN KEY (channel_id) REFERENCES im_channels(id),
  FOREIGN KEY (account_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_im_channel_members_channel ON im_channel_members(channel_id);
CREATE INDEX IF NOT EXISTS idx_im_channel_members_account ON im_channel_members(account_id);

-- 事件/消息表：uuid 为客户端生成的临时 ID，用于去重与回包
CREATE TABLE IF NOT EXISTS im_events (
  id TEXT PRIMARY KEY,
  channel_id INTEGER NOT NULL,
  sender_id TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'text',
  uuid TEXT,
  body TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  quote_event_id TEXT,
  related_event_id TEXT,
  FOREIGN KEY (channel_id) REFERENCES im_channels(id),
  FOREIGN KEY (sender_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_im_events_channel_created ON im_events(channel_id, created_at);
CREATE INDEX IF NOT EXISTS idx_im_events_uuid ON im_events(uuid);
