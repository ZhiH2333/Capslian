-- realms: 圈子
CREATE TABLE IF NOT EXISTS realms (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  description TEXT,
  avatar_url TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_realms_slug ON realms(slug);

-- realm_members: 圈子成员
CREATE TABLE IF NOT EXISTS realm_members (
  realm_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (realm_id, user_id),
  FOREIGN KEY (realm_id) REFERENCES realms(id),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_realm_members_user ON realm_members(user_id);
