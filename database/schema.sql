CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), phone TEXT UNIQUE NOT NULL,
 display_name TEXT, avatar_url TEXT, role TEXT NOT NULL DEFAULT 'user',
 status TEXT NOT NULL DEFAULT 'active', created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS otp_codes(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), phone TEXT NOT NULL, code_hash TEXT NOT NULL,
 attempts INT NOT NULL DEFAULT 0, expires_at TIMESTAMPTZ NOT NULL, created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS otp_phone_idx ON otp_codes(phone, created_at DESC);

CREATE TABLE IF NOT EXISTS devices(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID REFERENCES users(id) ON DELETE CASCADE,
 device_name TEXT, platform TEXT, push_token TEXT, last_seen TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS devices_user_idx ON devices(user_id);

CREATE TABLE IF NOT EXISTS conversations(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), type TEXT NOT NULL DEFAULT 'direct',
 title TEXT, created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS conversation_members(
 conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
 user_id UUID REFERENCES users(id) ON DELETE CASCADE, role TEXT DEFAULT 'member',
 PRIMARY KEY(conversation_id,user_id)
);
CREATE TABLE IF NOT EXISTS messages(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
 sender_id UUID REFERENCES users(id), body TEXT, media_url TEXT, message_type TEXT DEFAULT 'text',
 created_at TIMESTAMPTZ DEFAULT now(), deleted_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS messages_conv_idx ON messages(conversation_id,created_at);

CREATE TABLE IF NOT EXISTS statuses(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID REFERENCES users(id) ON DELETE CASCADE,
 media_url TEXT, caption TEXT, expires_at TIMESTAMPTZ, created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS reports(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), reporter_id UUID REFERENCES users(id),
 target_user_id UUID REFERENCES users(id), message_id UUID REFERENCES messages(id),
 reason TEXT, details TEXT, status TEXT DEFAULT 'open', created_at TIMESTAMPTZ DEFAULT now(), resolved_at TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS blocks(
 blocker_id UUID REFERENCES users(id) ON DELETE CASCADE, blocked_id UUID REFERENCES users(id) ON DELETE CASCADE,
 created_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY(blocker_id,blocked_id)
);
CREATE TABLE IF NOT EXISTS calls(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), conversation_id UUID REFERENCES conversations(id),
 caller_id UUID REFERENCES users(id), callee_id UUID REFERENCES users(id), type TEXT,
 started_at TIMESTAMPTZ, ended_at TIMESTAMPTZ, status TEXT
);
CREATE TABLE IF NOT EXISTS audit_logs(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), actor_user_id UUID REFERENCES users(id),
 action TEXT NOT NULL, target_type TEXT, target_id TEXT, metadata JSONB, created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS reports_status_idx ON reports(status);
CREATE INDEX IF NOT EXISTS audit_created_idx ON audit_logs(created_at);
