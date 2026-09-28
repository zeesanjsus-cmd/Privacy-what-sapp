require('dotenv').config();
const express = require('express');
const http = require('http');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const { Pool } = require('pg');
let firebaseAdmin = null;
try { firebaseAdmin = require('firebase-admin'); } catch {}

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: process.env.CORS_ORIGIN || '*', methods: ['GET','POST'] } });
const PORT = Number(process.env.PORT || 8080);
const JWT_SECRET = process.env.JWT_SECRET || 'dev-only-secret-change-me';
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const otpLimiter = rateLimit({ windowMs: 10 * 60 * 1000, max: 5, standardHeaders: true, legacyHeaders: false });
const apiLimiter = rateLimit({ windowMs: 60 * 1000, max: 180, standardHeaders: true, legacyHeaders: false });

app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(express.json({ limit: '2mb' }));
const mediaDir = path.join(process.cwd(), 'uploads');
fs.mkdirSync(mediaDir, { recursive: true });
const upload = multer({ dest: mediaDir, limits: { fileSize: 20 * 1024 * 1024 } });
app.use('/uploads', express.static(mediaDir, { maxAge: '1h' }));
app.use(apiLimiter);

const otpHash = (otp) => crypto.createHash('sha256').update(otp + (process.env.OTP_PEPPER || '')).digest('hex');
const normalizePhone = (phone) => String(phone || '').replace(/[^\d+]/g, '').replace(/^00/, '+');
const signToken = (user) => jwt.sign({ sub: user.id, role: user.role }, JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES_IN || '7d' });

async function db(text, params = []) { return pool.query(text, params); }

async function sendOtp(phone, otp) {
  // Provider adapters are intentionally credential-free. Configure Twilio Verify or another SMS provider in env.
  if (process.env.SMS_PROVIDER === 'console') {
    console.log('[DEV OTP]', phone, otp);
    return;
  }
  if (process.env.SMS_PROVIDER === 'twilio') {
    if (!process.env.TWILIO_ACCOUNT_SID || !process.env.TWILIO_AUTH_TOKEN || !process.env.TWILIO_VERIFY_SERVICE_SID) {
      throw new Error('Twilio configuration is incomplete');
    }
    const basic = Buffer.from(process.env.TWILIO_ACCOUNT_SID + ':' + process.env.TWILIO_AUTH_TOKEN).toString('base64');
    const body = new URLSearchParams({ To: phone, Channel: 'sms' });
    const r = await fetch(`https://verify.twilio.com/v2/Services/${process.env.TWILIO_VERIFY_SERVICE_SID}/Verifications`, {
      method: 'POST',
      headers: { Authorization: 'Basic ' + basic, 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });
    if (!r.ok) throw new Error('SMS provider rejected OTP request');
    return;
  }
  throw new Error('SMS provider is not configured');
}

async function pushNotification(userId, title, body, data = {}) {
  try {
    const result = await db('SELECT push_token FROM devices WHERE user_id=$1 AND push_token IS NOT NULL', [userId]);
    if (!result.rows.length) return { sent: 0 };
    if (process.env.FCM_ENABLED !== 'true' || !firebaseAdmin) return { sent: 0, queued: result.rows.length };
    if (!firebaseAdmin.apps.length) {
      const raw = process.env.FCM_SERVICE_ACCOUNT_JSON;
      if (!raw) return { sent: 0, queued: result.rows.length };
      const serviceAccount = JSON.parse(raw);
      firebaseAdmin.initializeApp({ credential: firebaseAdmin.credential.cert(serviceAccount) });
    }
    const tokens = result.rows.map(r => r.push_token).filter(Boolean);
    const response = await firebaseAdmin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k,v]) => [k, String(v)]))
    });
    return { sent: response.successCount, failed: response.failureCount };
  } catch (e) {
    console.error('push notification error', e.message);
    return { sent: 0 };
  }
}

async function auth(req, res, next) {
  try {
    const raw = req.headers.authorization || '';
    const token = raw.startsWith('Bearer ') ? raw.slice(7) : raw;
    const payload = jwt.verify(token, JWT_SECRET);
    const q = await db('SELECT id, phone, display_name, avatar_url, role, status FROM users WHERE id=$1', [payload.sub]);
    if (!q.rows[0] || q.rows[0].status !== 'active') return res.status(403).json({ error: 'account unavailable' });
    req.user = q.rows[0];
    next();
  } catch {
    res.status(401).json({ error: 'unauthorized' });
  }
}

function ownerOnly(req, res, next) {
  if (!req.user || !['owner', 'admin'].includes(req.user.role)) return res.status(403).json({ error: 'owner access required' });
  next();
}

app.get('/health', async (req, res) => {
  try { await db('SELECT 1'); res.json({ ok: true, service: 'privacy-whatsapp', database: 'up' }); }
  catch { res.status(503).json({ ok: false, service: 'privacy-whatsapp', database: 'down' }); }
});

app.post('/auth/request-otp', otpLimiter, async (req, res) => {
  const phone = normalizePhone(req.body?.phone);
  if (!/^\+[1-9]\d{7,14}$/.test(phone)) return res.status(400).json({ error: 'valid international phone required' });
  const otp = String(Math.floor(100000 + Math.random() * 900000));
  const hash = otpHash(otp);
  try {
    await db('DELETE FROM otp_codes WHERE phone=$1 OR expires_at < now()', [phone]);
    await db('INSERT INTO otp_codes(phone, code_hash, expires_at, attempts) VALUES($1,$2,now()+interval \'5 minutes\',0)', [phone, hash]);
    await sendOtp(phone, otp);
    res.json({ ok: true, message: 'OTP sent' });
  } catch (e) {
    console.error(e);
    res.status(503).json({ error: 'OTP service unavailable' });
  }
});

app.post('/auth/verify-otp', otpLimiter, async (req, res) => {
  const phone = normalizePhone(req.body?.phone);
  const otp = String(req.body?.otp || '').trim();
  if (!/^\+[1-9]\d{7,14}$/.test(phone) || !/^\d{6}$/.test(otp)) return res.status(400).json({ error: 'invalid phone or OTP' });
  try {
    const q = await db('SELECT * FROM otp_codes WHERE phone=$1 AND expires_at > now() ORDER BY created_at DESC LIMIT 1', [phone]);
    if (!q.rows[0]) return res.status(401).json({ error: 'OTP expired or not found' });
    if (q.rows[0].attempts >= 5) return res.status(429).json({ error: 'too many attempts' });
    if (q.rows[0].code_hash !== otpHash(otp)) {
      await db('UPDATE otp_codes SET attempts=attempts+1 WHERE id=$1', [q.rows[0].id]);
      return res.status(401).json({ error: 'invalid OTP' });
    }
    const ownerPhone = normalizePhone(process.env.OWNER_PHONE || '');
    const role = ownerPhone && phone === ownerPhone ? 'owner' : 'user';
    const u = await db(`INSERT INTO users(phone, role) VALUES($1,$2)
      ON CONFLICT(phone) DO UPDATE SET role=CASE WHEN users.role='owner' THEN 'owner' ELSE EXCLUDED.role END, updated_at=now()
      RETURNING id, phone, display_name, avatar_url, role, status`, [phone, role]);
    await db('DELETE FROM otp_codes WHERE phone=$1', [phone]);
    await db('INSERT INTO audit_logs(actor_user_id, action, target_type, target_id) VALUES($1,$2,$3,$4)', [u.rows[0].id, 'login', 'user', u.rows[0].id]);
    res.json({ token: signToken(u.rows[0]), user: u.rows[0] });
  } catch (e) { console.error(e); res.status(500).json({ error: 'authentication failed' }); }
});

app.get('/me', auth, (req, res) => res.json(req.user));

app.post('/devices', auth, async (req, res) => {
  const { pushToken, deviceName, platform } = req.body || {};
  if (!pushToken) return res.status(400).json({ error: 'pushToken required' });
  const q = await db(`INSERT INTO devices(user_id, device_name, platform, push_token, last_seen)
    VALUES($1,$2,$3,$4,now()) RETURNING id, device_name, platform, push_token, last_seen`, [req.user.id, deviceName || null, platform || null, pushToken]);
  res.status(201).json(q.rows[0]);
});

app.get('/users', auth, async (req, res) => {
  const q = await db(`SELECT id, phone, display_name, avatar_url, role, status FROM users
    WHERE id <> $1 AND status='active' ORDER BY COALESCE(display_name, phone)`, [req.user.id]);
  res.json(q.rows);
});

app.post('/conversations/direct', auth, async (req, res) => {
  const other = req.body?.userId;
  if (!other || other === req.user.id) return res.status(400).json({ error: 'valid userId required' });
  const existing = await db(`SELECT c.id FROM conversations c
    JOIN conversation_members a ON a.conversation_id=c.id AND a.user_id=$1
    JOIN conversation_members b ON b.conversation_id=c.id AND b.user_id=$2
    WHERE c.type='direct' LIMIT 1`, [req.user.id, other]);
  if (existing.rows[0]) return res.json({ id: existing.rows[0].id });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const c = await client.query('INSERT INTO conversations(type) VALUES(\'direct\') RETURNING id');
    await client.query('INSERT INTO conversation_members(conversation_id,user_id) VALUES($1,$2),($1,$3)', [c.rows[0].id, req.user.id, other]);
    await client.query('COMMIT');
    res.status(201).json({ id: c.rows[0].id });
  } catch (e) { await client.query('ROLLBACK'); res.status(500).json({ error: 'conversation creation failed' }); }
  finally { client.release(); }
});

app.get('/conversations', auth, async (req, res) => {
  const q = await db(`SELECT c.id,c.type,c.title,c.created_at,
    (SELECT m.body FROM messages m WHERE m.conversation_id=c.id ORDER BY m.created_at DESC LIMIT 1) AS last_message,
    (SELECT m.created_at FROM messages m WHERE m.conversation_id=c.id ORDER BY m.created_at DESC LIMIT 1) AS last_message_at
    FROM conversations c JOIN conversation_members cm ON cm.conversation_id=c.id
    WHERE cm.user_id=$1 ORDER BY COALESCE(last_message_at,c.created_at) DESC`, [req.user.id]);
  res.json(q.rows);
});

app.get('/conversations/:id/messages', auth, async (req, res) => {
  const member = await db('SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2', [req.params.id, req.user.id]);
  if (!member.rows[0]) return res.status(403).json({ error: 'not a member' });
  const q = await db(`SELECT id,conversation_id,sender_id,body,media_url,message_type,created_at,deleted_at
    FROM messages WHERE conversation_id=$1 AND deleted_at IS NULL ORDER BY created_at ASC LIMIT 500`, [req.params.id]);
  res.json(q.rows);
});

app.post('/conversations/:id/messages', auth, async (req, res) => {
  const member = await db('SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2', [req.params.id, req.user.id]);
  if (!member.rows[0]) return res.status(403).json({ error: 'not a member' });
  const body = String(req.body?.body || '').trim();
  const type = req.body?.messageType || 'text';
  if (!body && !req.body?.mediaUrl) return res.status(400).json({ error: 'message content required' });
  const q = await db(`INSERT INTO messages(conversation_id,sender_id,body,media_url,message_type)
    VALUES($1,$2,$3,$4,$5) RETURNING id,conversation_id,sender_id,body,media_url,message_type,created_at`,
    [req.params.id, req.user.id, body || null, req.body?.mediaUrl || null, type]);
  const msg = q.rows[0];
  io.to('conversation:' + req.params.id).emit('message', msg);
  const members = await db('SELECT user_id FROM conversation_members WHERE conversation_id=$1 AND user_id<>$2', [req.params.id, req.user.id]);
  for (const m of members.rows) await pushNotification(m.user_id, req.user.display_name || req.user.phone, body || 'New message', { conversationId: req.params.id, messageId: msg.id });
  res.status(201).json(msg);
});

app.post('/media/upload', auth, upload.single('file'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'file required' });
  const ext = path.extname(req.file.originalname || '').slice(0, 10).replace(/[^a-zA-Z0-9.]/g, '');
  const finalName = req.file.filename + ext;
  const finalPath = path.join(mediaDir, finalName);
  fs.renameSync(req.file.path, finalPath);
  const base = process.env.PUBLIC_BASE_URL || ('http://localhost:' + PORT);
  res.status(201).json({ url: base.replace(/\\/$/, '') + '/uploads/' + finalName, filename: req.file.originalname, mimeType: req.file.mimetype, size: req.file.size });
});

app.get('/statuses', auth, async (req, res) => {
  const q = await db(`SELECT s.id,s.user_id,s.media_url,s.caption,s.expires_at,s.created_at
    FROM statuses s
    WHERE (s.expires_at IS NULL OR s.expires_at > now())
      AND s.user_id <> $1
      AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.blocker_id=$1 AND b.blocked_id=s.user_id)
      AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.blocker_id=s.user_id AND b.blocked_id=$1)
    UNION ALL
    SELECT s.id,s.user_id,s.media_url,s.caption,s.expires_at,s.created_at
    FROM statuses s
    WHERE s.user_id=$1 AND (s.expires_at IS NULL OR s.expires_at > now())
    ORDER BY created_at DESC LIMIT 500`, [req.user.id]);
  res.json(q.rows);
});

app.post('/statuses', auth, async (req, res) => {
  const mediaUrl = req.body?.mediaUrl || null;
  const caption = req.body?.caption || null;
  if (!mediaUrl && !caption) return res.status(400).json({ error: 'status content required' });
  const q = await db(`INSERT INTO statuses(user_id,media_url,caption,expires_at)
    VALUES($1,$2,$3,now()+interval '24 hours')
    RETURNING id,user_id,media_url,caption,expires_at,created_at`, [req.user.id, mediaUrl, caption]);
  res.status(201).json(q.rows[0]);
});

app.delete('/statuses/:id', auth, async (req, res) => {
  const q = await db('DELETE FROM statuses WHERE id=$1 AND user_id=$2 RETURNING id', [req.params.id, req.user.id]);
  if (!q.rows[0]) return res.status(404).json({ error: 'status not found' });
  res.json({ ok: true });
});

app.patch('/me', auth, async (req, res) => {
  const displayName = req.body?.displayName;
  const avatarUrl = req.body?.avatarUrl;
  const q = await db(`UPDATE users SET display_name=COALESCE($1,display_name),avatar_url=COALESCE($2,avatar_url),updated_at=now()
    WHERE id=$3 RETURNING id,phone,display_name,avatar_url,role,status`, [displayName ?? null, avatarUrl ?? null, req.user.id]);
  res.json(q.rows[0]);
});

app.post('/blocks/:userId', auth, async (req, res) => {
  await db('INSERT INTO blocks(blocker_id,blocked_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [req.user.id, req.params.userId]);
  res.json({ ok: true });
});
app.delete('/blocks/:userId', auth, async (req, res) => {
  await db('DELETE FROM blocks WHERE blocker_id=$1 AND blocked_id=$2', [req.user.id, req.params.userId]);
  res.json({ ok: true });
});
app.post('/reports', auth, async (req, res) => {
  const q = await db(`INSERT INTO reports(reporter_id,target_user_id,message_id,reason,details)
    VALUES($1,$2,$3,$4,$5) RETURNING *`, [req.user.id, req.body?.targetUserId || null, req.body?.messageId || null, req.body?.reason || 'other', req.body?.details || null]);
  await db('INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,metadata) VALUES($1,$2,$3,$4,$5)', [req.user.id, 'report_created', 'report', q.rows[0].id, JSON.stringify({ reason: req.body?.reason || 'other' })]);
  res.status(201).json(q.rows[0]);
});

app.get('/owner/revenue-summary', auth, ownerOnly, async (req, res) => {
  const q = await db(`SELECT COALESCE(SUM(amount_minor),0)::bigint AS total_amount_minor,
    COUNT(*)::int AS events,
    COUNT(DISTINCT user_id)::int AS paying_users
    FROM revenue_events`);
  const r = await db(`SELECT COALESCE(SUM(points),0)::bigint AS points_issued FROM reward_transactions`);
  res.json({ revenue: q.rows[0], rewards: r.rows[0] });
});

app.get('/owner/reports', auth, ownerOnly, async (req, res) => res.json((await db('SELECT * FROM reports ORDER BY created_at DESC LIMIT 1000')).rows));
app.get('/owner/users', auth, ownerOnly, async (req, res) => res.json((await db('SELECT id,phone,display_name,role,status,created_at FROM users ORDER BY created_at DESC LIMIT 5000')).rows));
app.get('/owner/audit-logs', auth, ownerOnly, async (req, res) => res.json((await db('SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT 5000')).rows));

app.post('/owner/users/:id/:action', auth, ownerOnly, async (req, res) => {
  const allowed = ['suspend','block','restore'];
  if (!allowed.includes(req.params.action)) return res.status(400).json({ error: 'invalid action' });
  const status = req.params.action === 'restore' ? 'active' : req.params.action === 'suspend' ? 'suspended' : 'blocked';
  const q = await db('UPDATE users SET status=$1, updated_at=now() WHERE id=$2 RETURNING id,phone,display_name,role,status', [status, req.params.id]);
  if (!q.rows[0]) return res.status(404).json({ error: 'user not found' });
  await db('INSERT INTO audit_logs(actor_user_id,action,target_type,target_id) VALUES($1,$2,$3,$4)', [req.user.id, req.params.action, 'user', req.params.id]);
  res.json(q.rows[0]);
});

io.use((socket, next) => {
  try {
    const token = socket.handshake.auth?.token;
    socket.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch { next(new Error('unauthorized')); }
});

io.on('connection', (socket) => {
  socket.on('join', async (conversationId) => {
    try {
      const q = await db('SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2', [conversationId, socket.user.sub]);
      if (q.rows[0]) socket.join('conversation:' + conversationId);
    } catch {}
  });
  socket.on('message', async (m) => {
    if (!m?.conversationId || !m?.body) return;
    try {
      const q = await db('SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2', [m.conversationId, socket.user.sub]);
      if (!q.rows[0]) return;
      const saved = await db(`INSERT INTO messages(conversation_id,sender_id,body,message_type) VALUES($1,$2,$3,$4)
        RETURNING id,conversation_id,sender_id,body,message_type,created_at`, [m.conversationId, socket.user.sub, String(m.body).slice(0, 10000), 'text']);
      io.to('conversation:' + m.conversationId).emit('message', saved.rows[0]);
    } catch (e) { socket.emit('error', { error: 'message failed' }); }
  });
  for (const event of ['call:offer','call:answer','call:ice']) {
    socket.on(event, async (m) => {
      if (!m?.conversationId || !(await isMember(m.conversationId, socket.user.sub))) return;
      socket.to('conversation:' + m.conversationId).emit(event, { ...m, senderId: socket.user.sub });
    });
  }
});

server.listen(PORT, () => console.log('Privacy WhatsApp backend running on ' + PORT));
