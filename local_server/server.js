const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const http = require('http');
const https = require('https');
const zlib = require('zlib');
const crypto = require('crypto');
const multer = require('multer');
const { pipeline } = require('stream');
const { promisify } = require('util');
const { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } = require('@aws-sdk/client-s3');
const db = require('./server/db');
const { authenticate, requireAdmin, getOrInitInviteCode, generateInviteCode } = require('./server/auth');
const webpush = require('web-push');

const app = express();
const PORT = Number(process.env.PORT) || 3000;

let VAPID_PUBLIC_KEY = process.env.VAPID_PUBLIC_KEY || '';
let VAPID_PRIVATE_KEY = process.env.VAPID_PRIVATE_KEY || '';
let VAPID_SUBJECT = process.env.VAPID_SUBJECT || 'mailto:admin@example.com';
const ATTACHMENT_MAX_SIZE = 50 * 1024 * 1024;
const ATTACHMENTS_DRIVER = String(process.env.ATTACHMENTS_DRIVER || 'local').toLowerCase();
const ATTACHMENTS_DIR = process.env.ATTACHMENTS_DIR || path.join(__dirname, 'storage', 'attachments');
const ATTACHMENTS_TMP_DIR = path.join(ATTACHMENTS_DIR, '_tmp');
const ATTACHMENTS_S3_BUCKET = process.env.ATTACHMENTS_S3_BUCKET || process.env.S3_BUCKET || '';
const ATTACHMENTS_S3_REGION = process.env.ATTACHMENTS_S3_REGION || process.env.S3_REGION || 'auto';
const ATTACHMENTS_S3_ENDPOINT = process.env.ATTACHMENTS_S3_ENDPOINT || process.env.S3_ENDPOINT || '';
const ATTACHMENTS_S3_PREFIX = (() => {
    const raw = (process.env.ATTACHMENTS_S3_PREFIX || 'attachments/').replace(/^\/+/, '');
    return raw.endsWith('/') ? raw : `${raw}/`;
})();
const ATTACHMENTS_S3_FORCE_PATH_STYLE = String(process.env.ATTACHMENTS_S3_FORCE_PATH_STYLE || '').toLowerCase() === 'true';
const ATTACHMENTS_ALLOWED_EXTS = new Set([
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.md', '.csv', '.rtf',
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tif', '.tiff', '.svg',
    '.psd', '.psb', '.ai', '.sketch', '.fig', '.xd', '.indd'
]);
const PUSH_SCAN_INTERVAL_MS = 60 * 1000;
const PUSH_WINDOW_MS = 60 * 1000;
const streamPipeline = promisify(pipeline);
const isS3Driver = ATTACHMENTS_DRIVER === 's3' || ATTACHMENTS_DRIVER === 'r2';
const s3Client = isS3Driver ? new S3Client({
    region: ATTACHMENTS_S3_REGION,
    endpoint: ATTACHMENTS_S3_ENDPOINT || undefined,
    forcePathStyle: ATTACHMENTS_S3_FORCE_PATH_STYLE,
    credentials: process.env.ATTACHMENTS_S3_ACCESS_KEY_ID
        || process.env.ATTACHMENTS_S3_SECRET_ACCESS_KEY
        || process.env.S3_ACCESS_KEY_ID
        || process.env.S3_SECRET_ACCESS_KEY
        ? {
            accessKeyId: process.env.ATTACHMENTS_S3_ACCESS_KEY_ID || process.env.S3_ACCESS_KEY_ID || '',
            secretAccessKey: process.env.ATTACHMENTS_S3_SECRET_ACCESS_KEY || process.env.S3_SECRET_ACCESS_KEY || ''
        }
        : undefined
}) : null;

const isPushConfigured = () => !!(VAPID_PUBLIC_KEY && VAPID_PRIVATE_KEY);

const dbAll = (sql, params = []) => new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => (err ? reject(err) : resolve(rows)));
});

const dbRun = (sql, params = []) => new Promise((resolve, reject) => {
    db.run(sql, params, function(err) {
        if (err) return reject(err);
        resolve(this);
    });
});

const ensureDir = (dirPath) => {
    if (!fs.existsSync(dirPath)) fs.mkdirSync(dirPath, { recursive: true });
};

const fetchText = (url, { timeoutMs = 12000, maxRedirects = 3 } = {}) => new Promise((resolve, reject) => {

    const doRequest = (currentUrl, redirectsLeft) => {
        let parsed;
        try {
            parsed = new URL(currentUrl);
        } catch (e) {
            return reject(new Error('Invalid URL'));
        }

        const client = parsed.protocol === 'http:' ? http : https;
        const req = client.get(currentUrl, {
            headers: {
                'User-Agent': 'glass-todo-local',
                'Accept': 'application/json',
                'Accept-Encoding': 'gzip, deflate, br'
            }
        }, (resp) => {
            const code = resp.statusCode || 0;
            if ([301, 302, 303, 307, 308].includes(code) && resp.headers.location) {
                resp.resume();
                if (redirectsLeft <= 0) return reject(new Error('Too many redirects'));
                const nextUrl = new URL(resp.headers.location, currentUrl).toString();
                return doRequest(nextUrl, redirectsLeft - 1);
            }
            if (code !== 200) {
                resp.resume();
                return reject(new Error(`HTTP ${code}`));
            }

            const encoding = String(resp.headers['content-encoding'] || '').toLowerCase();
            let stream = resp;
            if (encoding === 'gzip') stream = resp.pipe(zlib.createGunzip());
            else if (encoding === 'deflate') stream = resp.pipe(zlib.createInflate());
            else if (encoding === 'br') stream = resp.pipe(zlib.createBrotliDecompress());

            let data = '';
            stream.setEncoding('utf8');
            stream.on('data', (chunk) => { data += chunk; });
            stream.on('end', () => resolve(data));
            stream.on('error', (err) => reject(err));
        });

        req.setTimeout(timeoutMs, () => {
            req.destroy(new Error('Request timeout'));
        });
        req.on('error', (err) => reject(err));
    };

    doRequest(url, maxRedirects);
});

const createAttachmentId = () => {
    if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
    return crypto.randomBytes(16).toString('hex');
};

const encodeRFC5987Value = (val) => encodeURIComponent(val)
    .replace(/['()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);

const buildDownloadDisposition = (filename) => {
    const safe = String(filename || 'attachment');
    const asciiFallback = safe.replace(/[^\x20-\x7E]/g, '_').replace(/"/g, "'");
    return `attachment; filename="${asciiFallback}"; filename*=UTF-8''${encodeRFC5987Value(safe)}`;
};

const maybeDecodeLatin1Filename = (name) => {
    if (!name) return '';
    const raw = String(name);
    if (!/[^\x00-\x7F]/.test(raw)) return raw;
    const decoded = Buffer.from(raw, 'latin1').toString('utf8');
    const hasCjk = /[\u4E00-\u9FFF]/.test(decoded);
    const rawHasCjk = /[\u4E00-\u9FFF]/.test(raw);
    if (hasCjk && !rawHasCjk) return decoded;
    return raw;
};

const normalizeOriginalName = (name) => {
    const decoded = maybeDecodeLatin1Filename(name);
    const safe = path.basename(String(decoded || '').trim());
    return safe || 'attachment';
};

const buildAttachmentRelPath = (id, ext) => `${id.slice(0, 2)}/${id}${ext}`;

const createUuid = () => createAttachmentId();

const parseBool = (value) => value === true || value === 1 || value === '1' || value === 'true';

const parseIntSafe = (value) => {
    const num = parseInt(value, 10);
    return Number.isFinite(num) ? num : null;
};

const clampLimit = (value, min = 1, max = 500, fallback = 200) => {
    const parsed = parseIntSafe(value);
    if (!Number.isFinite(parsed)) return fallback;
    return Math.min(max, Math.max(min, parsed));
};

const normalizeDateKey = (value) => {
    const raw = String(value || '').trim();
    if (!raw) return '';
    if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw;
    return '';
};

const parseJsonArray = (value) => {
    if (!value) return [];
    if (Array.isArray(value)) return value;
    if (typeof value === 'string') {
        try {
            const parsed = JSON.parse(value);
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            return [];
        }
    }
    return [];
};

const normalizeTags = (value) => parseJsonArray(value)
    .map((tag) => String(tag || '').trim())
    .filter((tag) => tag);

const normalizeTaskSubtasks = (input) => {
    let raw = input;
    if (typeof raw === 'string') {
        try {
            raw = JSON.parse(raw);
        } catch (e) {
            return [];
        }
    }
    if (!Array.isArray(raw)) return [];
    return raw
        .map((s) => {
            if (typeof s === 'string') {
                const title = s.trim();
                if (!title) return null;
                return { id: createUuid(), title, completed: false };
            }
            const title = String(s?.title || s?.text || s?.name || '').trim();
            if (!title) return null;
            const id = String(s?.id || s?.uuid || '').trim() || createUuid();
            return {
                id,
                title,
                completed: !!s?.completed
            };
        })
        .filter(Boolean);
};

const normalizeTaskAttachments = (input) => {
    let raw = input;
    if (typeof raw === 'string') {
        try {
            raw = JSON.parse(raw);
        } catch (e) {
            return [];
        }
    }
    if (!Array.isArray(raw)) return [];
    return raw
        .map((a) => {
            if (!a) return null;
            const id = String(a.id || '').trim();
            const name = String(a.name || a.original_name || '').trim();
            const mime = String(a.mime || a.mime_type || '').trim();
            const size = parseIntSafe(a.size) ?? 0;
            const createdAt = parseIntSafe(a.createdAt ?? a.created_at) ?? 0;
            if (!id || !name) return null;
            return {
                id,
                name,
                mime,
                size,
                createdAt
            };
        })
        .filter(Boolean);
};

const normalizeStatus = (value) => {
    const raw = String(value || '').toLowerCase();
    return raw === 'completed' ? 'completed' : 'todo';
};

const toUtcDateKey = (ms) => {
    const date = new Date(ms);
    const y = date.getUTCFullYear();
    const m = String(date.getUTCMonth() + 1).padStart(2, '0');
    const d = String(date.getUTCDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
};

const utcDayStartMs = (ms) => {
    const date = new Date(ms);
    return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
};

ensureDir(ATTACHMENTS_DIR);
ensureDir(ATTACHMENTS_TMP_DIR);

const attachmentUpload = multer({
    storage: multer.diskStorage({
        destination: (req, file, cb) => cb(null, ATTACHMENTS_TMP_DIR),
        filename: (req, file, cb) => {
            if (!req.attachmentId) req.attachmentId = createAttachmentId();
            const ext = path.extname(file.originalname || '').toLowerCase();
            req.attachmentExt = ext;
            cb(null, `${req.attachmentId}${ext}.upload`);
        }
    }),
    limits: { fileSize: ATTACHMENT_MAX_SIZE },
    fileFilter: (req, file, cb) => {
        const ext = path.extname(file.originalname || '').toLowerCase();
        if (!ext || !ATTACHMENTS_ALLOWED_EXTS.has(ext)) {
            return cb(new Error('Unsupported file type'));
        }
        cb(null, true);
    }
});

const storeAttachmentFile = async ({ tmpPath, id, ext, mimeType, originalName, size }) => {
    if (isS3Driver) {
        if (!ATTACHMENTS_S3_BUCKET) throw new Error('Missing S3 bucket configuration');
        const key = `${ATTACHMENTS_S3_PREFIX}${id}${ext}`;
        const body = fs.createReadStream(tmpPath);
        await s3Client.send(new PutObjectCommand({
            Bucket: ATTACHMENTS_S3_BUCKET,
            Key: key,
            Body: body,
            ContentType: mimeType,
            Metadata: { original_name: encodeURIComponent(originalName) },
            ContentLength: size
        }));
        fs.unlink(tmpPath, () => {});
        return { storageDriver: ATTACHMENTS_DRIVER, storagePath: key };
    }
    const relPath = buildAttachmentRelPath(id, ext);
    const absPath = path.join(ATTACHMENTS_DIR, relPath);
    ensureDir(path.dirname(absPath));
    fs.renameSync(tmpPath, absPath);
    return { storageDriver: 'local', storagePath: relPath };
};

const deleteAttachmentFile = async ({ storageDriver, storagePath }) => {
    if (storageDriver === 'local') {
        const absPath = path.join(ATTACHMENTS_DIR, storagePath);
        if (fs.existsSync(absPath)) fs.unlinkSync(absPath);
        return;
    }
    if (isS3Driver) {
        if (!ATTACHMENTS_S3_BUCKET) throw new Error('Missing S3 bucket configuration');
        await s3Client.send(new DeleteObjectCommand({
            Bucket: ATTACHMENTS_S3_BUCKET,
            Key: storagePath
        }));
    }
};

const loadVapidFromDb = async () => {
    const rows = await dbAll(
        "SELECT key, value FROM settings WHERE key IN ('vapid_public_key','vapid_private_key','vapid_subject')"
    );
    const map = {};
    rows.forEach((row) => { map[row.key] = row.value; });
    return map;
};

const saveVapidToDb = async ({ publicKey, privateKey, subject }) => {
    await dbRun("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", ['vapid_public_key', publicKey]);
    await dbRun("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", ['vapid_private_key', privateKey]);
    await dbRun("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", ['vapid_subject', subject]);
};

const ensureVapidKeys = async () => {
    if (isPushConfigured()) {
        webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
        return;
    }
    try {
        const stored = await loadVapidFromDb();
        if (!VAPID_PUBLIC_KEY && stored.vapid_public_key) VAPID_PUBLIC_KEY = stored.vapid_public_key;
        if (!VAPID_PRIVATE_KEY && stored.vapid_private_key) VAPID_PRIVATE_KEY = stored.vapid_private_key;
        if (!process.env.VAPID_SUBJECT && stored.vapid_subject) VAPID_SUBJECT = stored.vapid_subject;
    } catch (e) {
        console.warn('vapid load failed', e);
    }

    if (!isPushConfigured()) {
        const generated = webpush.generateVAPIDKeys();
        VAPID_PUBLIC_KEY = generated.publicKey;
        VAPID_PRIVATE_KEY = generated.privateKey;
        if (!VAPID_SUBJECT) VAPID_SUBJECT = 'mailto:admin@example.com';
        try {
            await saveVapidToDb({
                publicKey: VAPID_PUBLIC_KEY,
                privateKey: VAPID_PRIVATE_KEY,
                subject: VAPID_SUBJECT
            });
        } catch (e) {
            console.warn('vapid save failed', e);
        }
    }

    if (isPushConfigured()) {
        webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
    }
};

app.use(cors());
app.use(bodyParser.json());
app.get('/config.json', (req, res) => {
    res.json({
        apiBaseUrl: process.env.API_BASE_URL || '',
        useLocalStorage: String(process.env.USE_LOCAL_STORAGE || '').toLowerCase() === 'true',
        holidayJsonUrl: process.env.HOLIDAY_JSON_URL || '',
        appTitle: process.env.APP_TITLE || 'Glass Todo'
    });
});
app.use(express.static(path.join(__dirname, 'public')));

const holidaysDir = path.join(__dirname, 'public', 'holidays');
if (!fs.existsSync(holidaysDir)) fs.mkdirSync(holidaysDir, { recursive: true });

let firebaseAdmin = null;
let firebaseMessaging = null;

const isFcmConfigured = () => !!firebaseMessaging;

const ensureFirebaseAdmin = async () => {
    if (firebaseMessaging) return true;
    let adminLib = null;
    try {
        adminLib = require('firebase-admin');
    } catch (e) {
        return false;
    }

    try {
        if (adminLib.apps && adminLib.apps.length) {
            firebaseAdmin = adminLib;
            firebaseMessaging = adminLib.messaging();
            return true;
        }

        const fromJson = String(process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '').trim();
        const fromPath = String(process.env.FIREBASE_SERVICE_ACCOUNT_PATH || '').trim();

        let credential = null;
        if (fromJson) {
            credential = adminLib.credential.cert(JSON.parse(fromJson));
        } else if (fromPath && fs.existsSync(fromPath)) {
            const raw = fs.readFileSync(fromPath, 'utf8');
            credential = adminLib.credential.cert(JSON.parse(raw));
        } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
            credential = adminLib.credential.applicationDefault();
        }

        if (!credential) return false;

        adminLib.initializeApp({ credential });
        firebaseAdmin = adminLib;
        firebaseMessaging = adminLib.messaging();
        return true;
    } catch (e) {
        console.warn('firebase-admin init failed', e);
        return false;
    }
};

const buildPushPayload = (task) => {
    const when = task.date ? `${task.date}${task.start ? ` ${task.start}` : ''}` : '';
    return {
        title: '开始时间提醒',
        body: when ? `${task.title} (${when})` : task.title,
        url: '/',
        tag: `task-${task.id}`
    };
};

const sendPushToUser = async (username, payload) => {
    if (!isPushConfigured()) return false;
    let subs = [];
    try {
        subs = await dbAll("SELECT endpoint, p256dh, auth FROM push_subscriptions WHERE username = ?", [username]);
    } catch (e) {
        console.warn('push load subscriptions failed', e);
        return false;
    }
    if (!subs.length) return false;
    const message = JSON.stringify(payload);
    const sendJobs = subs.map(async (sub) => {
        const subscription = {
            endpoint: sub.endpoint,
            keys: { p256dh: sub.p256dh, auth: sub.auth }
        };
        try {
            await webpush.sendNotification(subscription, message);
        } catch (err) {
            const code = err?.statusCode;
            if (code === 404 || code === 410) {
                db.run("DELETE FROM push_subscriptions WHERE endpoint = ?", [sub.endpoint]);
            } else {
                console.warn('push send failed', code || err);
            }
        }
    });
    await Promise.allSettled(sendJobs);
    return true;
};

const sendFcmToUser = async (username, payload) => {
    const ready = await ensureFirebaseAdmin();
    if (!ready || !firebaseMessaging) return false;

    let rows = [];
    try {
        rows = await dbAll("SELECT token FROM fcm_tokens WHERE username = ?", [username]);
    } catch (e) {
        console.warn('fcm load tokens failed', e);
        return false;
    }
    const tokens = rows.map((r) => String(r.token || '').trim()).filter((t) => t.length > 0);
    if (!tokens.length) return false;

    const title = String(payload?.title || '').trim();
    const body = String(payload?.body || '').trim();
    const url = String(payload?.url || '/').trim() || '/';
    const tag = String(payload?.tag || '').trim();

    const message = {
        tokens,
        notification: title || body ? { title, body } : undefined,
        data: {
            ...(title ? { title } : {}),
            ...(body ? { body } : {}),
            url,
            ...(tag ? { tag } : {})
        }
    };

    try {
        const resp = await firebaseMessaging.sendEachForMulticast(message);
        const invalidIndexes = [];
        (resp.responses || []).forEach((r, idx) => {
            const err = r?.error;
            const code = err?.code || '';
            if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
                invalidIndexes.push(idx);
            }
        });
        if (invalidIndexes.length) {
            const invalidTokens = invalidIndexes.map((idx) => tokens[idx]).filter(Boolean);
            for (const t of invalidTokens) {
                db.run("DELETE FROM fcm_tokens WHERE token = ?", [t]);
            }
        }
        return (resp.successCount || 0) > 0;
    } catch (e) {
        console.warn('fcm send failed', e);
        return false;
    }
};

const scanAndSendReminders = async () => {
    const pushReady = isPushConfigured();
    const fcmReady = await ensureFirebaseAdmin();
    if (!pushReady && !fcmReady) return;

    const now = Date.now();
    const windowEnd = now + PUSH_WINDOW_MS;

    let tasks = [];
    try {
        tasks = await dbAll(
            `SELECT id, username, title, due_date, start_time, remind_at, notified_at
             FROM tasks_v2
             WHERE deleted_at IS NULL
               AND status != ?
               AND remind_at IS NOT NULL
               AND remind_at >= ? AND remind_at < ?
               AND (notified_at IS NULL OR notified_at < remind_at)`,
            ['completed', now, windowEnd]
        );
    } catch (e) {
        console.warn('reminder scan failed', e);
        return;
    }

    for (const task of tasks) {
        const date = String(task.due_date || '').trim();
        const start = String(task.start_time || '').trim();
        const when = date ? `${date}${start ? ` ${start}` : ''}` : '';
        const payload = {
            title: '开始时间提醒',
            body: when ? `${task.title} (${when})` : task.title,
            url: '/',
            tag: `task-${task.id}`
        };

        let sent = false;
        if (fcmReady) sent = (await sendFcmToUser(task.username, payload)) || sent;
        if (pushReady) sent = (await sendPushToUser(task.username, payload)) || sent;

        if (sent) {
            try {
                await dbRun("UPDATE tasks_v2 SET notified_at = ? WHERE id = ?", [now, task.id]);
            } catch (e) {}
        }
    }
};

let pushScanRunning = false;
setInterval(() => {
    if (pushScanRunning) return;
    pushScanRunning = true;
    scanAndSendReminders().finally(() => { pushScanRunning = false; });
}, PUSH_SCAN_INTERVAL_MS);

const getPomodoroDefaults = () => ({
    workMin: 25,
    shortBreakMin: 5,
    longBreakMin: 15,
    longBreakEvery: 4,
    autoStartNext: false,
    autoStartBreak: false,
    autoStartWork: false,
    autoFinishTask: false
});

const upsertPomodoroDailyStats = async (username, dateKey, workMinutes = 0, breakMinutes = 0) => {
    const rows = await dbAll(
        "SELECT work_sessions, work_minutes, break_minutes FROM pomodoro_daily_stats WHERE username = ? AND date_key = ?",
        [username, dateKey]
    );
    const updatedAt = Date.now();
    if (!rows.length) {
        await dbRun(
            "INSERT INTO pomodoro_daily_stats (username, date_key, work_sessions, work_minutes, break_minutes, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            [username, dateKey, workMinutes > 0 ? 1 : 0, workMinutes, breakMinutes, updatedAt]
        );
        return;
    }
    const current = rows[0];
    const nextSessions = current.work_sessions + (workMinutes > 0 ? 1 : 0);
    const nextWork = current.work_minutes + workMinutes;
    const nextBreak = current.break_minutes + breakMinutes;
    await dbRun(
        "UPDATE pomodoro_daily_stats SET work_sessions = ?, work_minutes = ?, break_minutes = ?, updated_at = ? WHERE username = ? AND date_key = ?",
        [nextSessions, nextWork, nextBreak, updatedAt, username, dateKey]
    );
};

const getUserSettingsDefaults = () => ({
    profile: {
        nickname: '',
        avatar: ''
    },
    preferences: {
        defaultView: 'inbox',
        undoEnabled: true,
        undoSeconds: 2,
        defaultSort: 'manual',
        theme: 'system',
        colorTheme: 'default',
        weekStart: 'monday',
        calendarTimelineDefaultHour: 8,
        shortcutsEnabled: true,
        naturalLanguageEnabled: true,
        matrixScope: 'today',
        matrixTodayOnly: true
    },
    notifications: {
        enabled: false,
        leadMinutes: 0,
        quietHours: { start: '22:00', end: '08:00' },
        dueReminder: true,
        planStartReminder: true
    },
    data: {
        backup: {
            enabled: false,
            frequency: 'weekly',
            keep: 10,
            location: 'server',
            serverPath: ''
        },
        sync: {
            mode: 'server',
            conflictStrategy: 'latest'
        },
        clearCompletedRetentionDays: 30
    },
    advanced: {
        nlpExperimental: false,
        lowEnergySortExperimental: false
    },
    viewSettings: { calendar: true, matrix: true, pomodoro: true },
    calendarDefaultMode: 'day',
    autoMigrateEnabled: true,
    pushEnabled: false,
    calendarSettings: {
        showTime: true,
        showTags: true,
        showLunar: true,
        showHoliday: true,
        taskBlockShowStartTimeDay: true,
        taskBlockShowTagsDay: true,
        taskBlockShowStartTimeWeek: true,
        taskBlockShowTagsWeek: true,
        taskBlockShowStartTimeMonth: true,
        taskBlockShowTagsMonth: true
    }
});

const sanitizeUserSettings = (input = {}) => {
    const defaults = getUserSettingsDefaults();
    const viewSettings = { ...defaults.viewSettings, ...(input.viewSettings || {}) };
    const calendarSettings = { ...defaults.calendarSettings, ...(input.calendarSettings || {}) };
    const mode = ['day', 'week', 'month'].includes(input.calendarDefaultMode) ? input.calendarDefaultMode : defaults.calendarDefaultMode;

    const safeString = (value, max = 200) => {
        if (value === null || typeof value === 'undefined') return '';
        return String(value).trim().slice(0, max);
    };

    const pickOne = (value, allowed, fallback) => {
        const raw = safeString(value, 60);
        return allowed.includes(raw) ? raw : fallback;
    };

    const parseBoolStrict = (value, fallback) => {
        if (typeof value === 'boolean') return value;
        return fallback;
    };

    const clampInt = (value, fallback, min, max) => {
        const parsed = parseInt(value, 10);
        if (!Number.isFinite(parsed)) return fallback;
        return Math.min(max, Math.max(min, parsed));
    };

    const parseLead = (value) => {
        const allowed = [0, 5, 10, 30];
        const parsed = parseInt(value, 10);
        if (!Number.isFinite(parsed)) return defaults.notifications.leadMinutes;
        return allowed.includes(parsed) ? parsed : defaults.notifications.leadMinutes;
    };

    const parseTimeHHmm = (value, fallback) => {
        const raw = safeString(value, 10);
        if (!raw) return fallback;
        if (!/^\d{2}:\d{2}$/.test(raw)) return fallback;
        const [hh, mm] = raw.split(':').map(v => parseInt(v, 10));
        if (!Number.isFinite(hh) || !Number.isFinite(mm)) return fallback;
        if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return fallback;
        return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
    };

    const profile = input.profile && typeof input.profile === 'object' ? input.profile : {};
    const preferences = input.preferences && typeof input.preferences === 'object' ? input.preferences : {};
    const notifications = input.notifications && typeof input.notifications === 'object' ? input.notifications : {};
    const data = input.data && typeof input.data === 'object' ? input.data : {};
    const backup = data.backup && typeof data.backup === 'object' ? data.backup : {};
    const sync = data.sync && typeof data.sync === 'object' ? data.sync : {};
    const advanced = input.advanced && typeof input.advanced === 'object' ? input.advanced : {};

    const defaultView = pickOne(
        preferences.defaultView,
        ['inbox', 'today', 'tomorrow', 'next7', 'all', 'checklists', 'matrix', 'calendar', 'timeTracking', 'pomodoro', 'stats'],
        defaults.preferences.defaultView
    );
    const undoSeconds = [2, 5].includes(parseInt(preferences.undoSeconds, 10)) ? parseInt(preferences.undoSeconds, 10) : defaults.preferences.undoSeconds;
    const defaultSort = pickOne(preferences.defaultSort, ['manual', 'quadrant', 'due', 'created'], defaults.preferences.defaultSort);
    const theme = pickOne(preferences.theme, ['light', 'dark', 'system'], defaults.preferences.theme);

    const colorThemeRaw = safeString(preferences.colorTheme, 60).toLowerCase();
    const colorThemeAllowed = ['default', 'sea', 'sunrise', 'ice'];
    const colorTheme = colorThemeAllowed.includes(colorThemeRaw) ? colorThemeRaw : defaults.preferences.colorTheme;

    const matrixScopeRaw = safeString(preferences.matrixScope, 20).toLowerCase();
    const matrixScopeAllowed = ['today', '3days', 'all'];
    const matrixScope = matrixScopeAllowed.includes(matrixScopeRaw)
        ? matrixScopeRaw
        : defaults.preferences.matrixScope;
    const matrixTodayOnly = matrixScope === 'today';
    const weekStart = pickOne(preferences.weekStart, ['monday', 'sunday'], defaults.preferences.weekStart);
    const calendarTimelineDefaultHour = clampInt(
        preferences.calendarTimelineDefaultHour,
        defaults.preferences.calendarTimelineDefaultHour,
        0,
        23
    );

    const notificationsEnabled = typeof notifications.enabled === 'boolean'
        ? notifications.enabled
        : (typeof input.pushEnabled === 'boolean' ? input.pushEnabled : defaults.notifications.enabled);

    return {
        profile: {
            nickname: safeString(profile.nickname, 50),
            avatar: safeString(profile.avatar, 32)
        },
        preferences: {
            defaultView,
            undoEnabled: parseBoolStrict(preferences.undoEnabled, defaults.preferences.undoEnabled),
            undoSeconds,
            defaultSort,
            theme,
            colorTheme,
            weekStart,
            calendarTimelineDefaultHour,
            shortcutsEnabled: parseBoolStrict(preferences.shortcutsEnabled, defaults.preferences.shortcutsEnabled),
            naturalLanguageEnabled: parseBoolStrict(preferences.naturalLanguageEnabled, defaults.preferences.naturalLanguageEnabled),
            matrixScope,
            matrixTodayOnly
        },
        notifications: {
            enabled: notificationsEnabled,
            leadMinutes: parseLead(notifications.leadMinutes),
            quietHours: {
                start: parseTimeHHmm(notifications?.quietHours?.start, defaults.notifications.quietHours.start),
                end: parseTimeHHmm(notifications?.quietHours?.end, defaults.notifications.quietHours.end)
            },
            dueReminder: parseBoolStrict(notifications.dueReminder, defaults.notifications.dueReminder),
            planStartReminder: parseBoolStrict(notifications.planStartReminder, defaults.notifications.planStartReminder)
        },
        data: {
            backup: {
                enabled: parseBoolStrict(backup.enabled, defaults.data.backup.enabled),
                frequency: pickOne(backup.frequency, ['daily', 'weekly'], defaults.data.backup.frequency),
                keep: clampInt(backup.keep, defaults.data.backup.keep, 1, 50),
                location: pickOne(backup.location, ['local', 'server'], defaults.data.backup.location),
                serverPath: safeString(backup.serverPath, 260)
            },
            sync: {
                mode: pickOne(sync.mode, ['local', 'server'], defaults.data.sync.mode),
                conflictStrategy: pickOne(sync.conflictStrategy, ['latest', 'manual', 'duplicate'], defaults.data.sync.conflictStrategy)
            },
            clearCompletedRetentionDays: [30, 90, -1].includes(parseInt(data.clearCompletedRetentionDays, 10))
                ? parseInt(data.clearCompletedRetentionDays, 10)
                : defaults.data.clearCompletedRetentionDays
        },
        advanced: {
            nlpExperimental: parseBoolStrict(advanced.nlpExperimental, defaults.advanced.nlpExperimental),
            lowEnergySortExperimental: parseBoolStrict(advanced.lowEnergySortExperimental, defaults.advanced.lowEnergySortExperimental)
        },
        viewSettings: {
            calendar: !!viewSettings.calendar,
            matrix: !!viewSettings.matrix,
            pomodoro: !!viewSettings.pomodoro
        },
        calendarDefaultMode: mode,
        autoMigrateEnabled: typeof input.autoMigrateEnabled === 'boolean' ? input.autoMigrateEnabled : defaults.autoMigrateEnabled,
        pushEnabled: notificationsEnabled,
        calendarSettings: {
            showTime: !!calendarSettings.showTime,
            showTags: !!calendarSettings.showTags,
            showLunar: !!calendarSettings.showLunar,
            showHoliday: !!calendarSettings.showHoliday,
            taskBlockShowStartTimeDay: !!calendarSettings.taskBlockShowStartTimeDay,
            taskBlockShowTagsDay: !!calendarSettings.taskBlockShowTagsDay,
            taskBlockShowStartTimeWeek: !!calendarSettings.taskBlockShowStartTimeWeek,
            taskBlockShowTagsWeek: !!calendarSettings.taskBlockShowTagsWeek,
            taskBlockShowStartTimeMonth: !!calendarSettings.taskBlockShowStartTimeMonth,
            taskBlockShowTagsMonth: !!calendarSettings.taskBlockShowTagsMonth
        }
    };
};

// --- API 路由 ---

// 1. 登录/注册
app.all('/api/login', authenticate, (req, res) => {
    res.json({ 
        success: true, 
        username: req.user.username,
        isAdmin: !!req.user.is_admin 
    });
});

// 2. 数据同步
app.get('/api/data', authenticate, (req, res) => {
    db.get("SELECT json_data, version FROM data WHERE username = ?", [req.user.username], (err, row) => {
        res.json({ data: row ? JSON.parse(row.json_data) : [], version: row ? row.version : 0 });
    });
});

app.post('/api/data', authenticate, (req, res) => {
    const { data, version, force } = req.body;
    db.get("SELECT version FROM data WHERE username = ?", [req.user.username], (err, row) => {
        const serverVersion = row ? row.version : 0;
        if (!force && version < serverVersion) {
            return res.status(409).json({ error: "Conflict", serverVersion, message: "云端数据更新" });
        }
        const newVersion = Date.now();
        db.run(`INSERT OR REPLACE INTO data (username, json_data, version) VALUES (?, ?, ?)`, 
            [req.user.username, JSON.stringify(data), newVersion], 
            () => res.json({ success: true, version: newVersion })
        );
    });
});

// Checklists
const mapChecklistRow = (row = {}) => ({
    id: Number(row.id),
    name: row.name || '',
    owner: row.owner || row.owner_user || row.owner_username || '',
    sharedCount: Number(row.shared_count || 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at
});
const normalizeChecklistSubtasks = (input) => {
    let raw = input;
    if (typeof raw === 'string') {
        try {
            raw = JSON.parse(raw);
        } catch (e) {
            return [];
        }
    }
    if (!Array.isArray(raw)) return [];
    return raw
        .map((s) => {
            if (typeof s === 'string') {
                return { title: s.trim(), completed: false, note: '' };
            }
            const title = String(s?.title || s?.text || s?.name || '').trim();
            return {
                title,
                completed: !!s?.completed,
                note: String(s?.note || '').trim()
            };
        })
        .filter(s => s.title);
};
const parseChecklistSubtasks = (raw) => {
    if (!raw) return [];
    try {
        return normalizeChecklistSubtasks(JSON.parse(raw));
    } catch (e) {
        return [];
    }
};
const mapChecklistItemRow = (row = {}) => ({
    id: Number(row.id),
    listId: Number(row.list_id),
    columnId: row.column_id === null || row.column_id === undefined ? null : Number(row.column_id),
    title: row.title || '',
    completed: !!row.completed,
    completedBy: row.completed_by || '',
    notes: row.notes || '',
    subtasks: parseChecklistSubtasks(row.subtasks_json),
    createdAt: row.created_at,
    updatedAt: row.updated_at
});
const getChecklistAccess = async (listId, username) => {
    const rows = await dbAll(
        `SELECT c.id, c.name, c.owner, c.created_at, c.updated_at, s.shared_user, s.can_edit
         FROM checklists c
         LEFT JOIN checklist_shares s ON s.list_id = c.id AND s.shared_user = ?
         WHERE c.id = ?`,
        [username, listId]
    );
    const row = rows[0];
    if (!row) return null;
    if (row.owner === username) {
        return { list: row, role: 'owner', canEdit: true };
    }
    if (row.shared_user === username) {
        return {
            list: row,
            role: 'shared',
            canEdit: !!row.can_edit
        };
    }
    return null;
};

const assertChecklistOwner = async (listId, username) => {
    const rows = await dbAll(
        "SELECT id, name, owner, created_at, updated_at FROM checklists WHERE id = ? AND owner = ?",
        [listId, username]
    );
    return rows[0] || null;
};

app.get('/api/checklists', authenticate, async (req, res) => {
    try {
        const rows = await dbAll(
            `SELECT c.id, c.name, c.owner, c.created_at, c.updated_at,
                    COUNT(DISTINCT s.shared_user) AS shared_count
             FROM checklists c
             LEFT JOIN checklist_shares s ON s.list_id = c.id
             WHERE c.owner = ? OR s.shared_user = ?
             GROUP BY c.id, c.name, c.owner, c.created_at, c.updated_at
             ORDER BY c.created_at ASC`,
            [req.user.username, req.user.username]
        );
        res.json({ lists: rows.map(mapChecklistRow) });
    } catch (e) {
        res.status(500).json({ error: 'Failed to load checklists' });
    }
});

app.post('/api/checklists', authenticate, async (req, res) => {
    const name = String(req.body.name || '').trim();
    if (!name) return res.status(400).json({ error: 'Name is required' });
    const now = Date.now();
    try {
        const result = await dbRun(
            "INSERT INTO checklists (owner, name, created_at, updated_at) VALUES (?, ?, ?, ?)",
            [req.user.username, name, now, now]
        );
        res.json({ success: true, list: { id: result.lastID, name, owner: req.user.username, createdAt: now, updatedAt: now } });
    } catch (e) {
        res.status(500).json({ error: 'Failed to create checklist' });
    }
});

app.patch('/api/checklists/:id', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    if (!Number.isFinite(listId)) return res.status(400).json({ error: 'Invalid checklist id' });
    const name = String(req.body.name || '').trim();
    if (!name) return res.status(400).json({ error: 'Name is required' });
    const now = Date.now();
    try {
        const access = await getChecklistAccess(listId, req.user.username);
        if (!access) return res.status(404).json({ error: '清单不存在或无权限' });
        if (access.role !== 'owner' && !access.canEdit) return res.status(403).json({ error: '无权编辑该清单' });
        await dbRun("UPDATE checklists SET name = ?, updated_at = ? WHERE id = ?", [name, now, listId]);
        res.json({ success: true, list: { id: listId, name, owner: access.list.owner, createdAt: access.list.created_at, updatedAt: now } });
    } catch (e) {
        res.status(500).json({ error: 'Failed to update checklist' });
    }
});

app.delete('/api/checklists/:id', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    if (!Number.isFinite(listId)) return res.status(400).json({ error: 'Invalid checklist id' });
    try {
        const owned = await assertChecklistOwner(listId, req.user.username);
        if (!owned) return res.status(404).json({ error: '清单不存在或无权限' });
        await dbRun("DELETE FROM checklist_items WHERE list_id = ?", [listId]);
        await dbRun("DELETE FROM checklist_shares WHERE list_id = ?", [listId]);
        await dbRun("DELETE FROM checklist_columns WHERE list_id = ?", [listId]);
        await dbRun("DELETE FROM checklists WHERE id = ?", [listId]);
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: 'Failed to delete checklist' });
    }
});

app.get('/api/checklists/:id/columns', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    if (!Number.isFinite(listId)) return res.status(400).json({ error: 'Invalid checklist id' });
    try {
        const access = await getChecklistAccess(listId, req.user.username);
        if (!access) return res.status(404).json({ error: '清单不存在或无权限' });
        const rows = await dbAll(
            "SELECT id, list_id, name, sort_order, created_at, updated_at FROM checklist_columns WHERE list_id = ? ORDER BY sort_order ASC, id ASC",
            [listId]
        );
        res.json({
            columns: rows.map(r => ({
                id: Number(r.id),
                listId: Number(r.list_id),
                name: r.name || '',
                sortOrder: Number(r.sort_order) || 0,
                createdAt: r.created_at,
                updatedAt: r.updated_at
            }))
        });
    } catch (e) {
        res.status(500).json({ error: 'Failed to load checklist columns' });
    }
});

app.post('/api/checklists/:id/columns', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    if (!Number.isFinite(listId)) return res.status(400).json({ error: 'Invalid checklist id' });
    const name = String(req.body.name || '').trim();
    if (!name) return res.status(400).json({ error: 'Name is required' });
    try {
        const access = await getChecklistAccess(listId, req.user.username);
        if (!access) return res.status(404).json({ error: '清单不存在或无权限' });
        if (access.role !== 'owner' && !access.canEdit) return res.status(403).json({ error: '无权编辑该清单' });
        const rows = await dbAll("SELECT MAX(sort_order) AS max_order FROM checklist_columns WHERE list_id = ?", [listId]);
        const nextOrder = (rows[0]?.max_order || 0) + 1;
        const now = Date.now();
        const result = await dbRun(
            "INSERT INTO checklist_columns (list_id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            [listId, name, nextOrder, now, now]
        );
        res.json({ success: true, column: { id: result.lastID, listId, name, sortOrder: nextOrder, createdAt: now, updatedAt: now } });
    } catch (e) {
        res.status(500).json({ error: 'Failed to create checklist column' });
    }
});

app.patch('/api/checklists/:id/columns/:columnId', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    const columnId = parseInt(req.params.columnId, 10);
    if (!Number.isFinite(listId) || !Number.isFinite(columnId)) return res.status(400).json({ error: 'Invalid id' });
    const name = String(req.body.name || '').trim();
    if (!name) return res.status(400).json({ error: 'Name is required' });
    try {
        const access = await getChecklistAccess(listId, req.user.username);
        if (!access) return res.status(404).json({ error: '清单不存在或无权限' });
        if (access.role !== 'owner' && !access.canEdit) return res.status(403).json({ error: '无权编辑该清单' });
        const rows = await dbAll(
            "SELECT id, sort_order, created_at FROM checklist_columns WHERE id = ? AND list_id = ?",
            [columnId, listId]
        );
        const column = rows[0];
        if (!column) return res.status(404).json({ error: '栏目不存在' });
        const now = Date.now();
        await dbRun("UPDATE checklist_columns SET name = ?, updated_at = ? WHERE id = ? AND list_id = ?", [name, now, columnId, listId]);
        res.json({ success: true, column: { id: columnId, listId, name, sortOrder: Number(column.sort_order) || 0, createdAt: column.created_at, updatedAt: now } });
    } catch (e) {
        res.status(500).json({ error: 'Failed to update checklist column' });
    }
});

app.delete('/api/checklists/:id/columns/:columnId', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    const columnId = parseInt(req.params.columnId, 10);
    if (!Number.isFinite(listId) || !Number.isFinite(columnId)) return res.status(400).json({ error: 'Invalid id' });
    try {
        const access = await getChecklistAccess(listId, req.user.username);
        if (!access) return res.status(404).json({ error: '清单不存在或无权限' });
        if (access.role !== 'owner' && !access.canEdit) return res.status(403).json({ error: '无权编辑该清单' });
        const columns = await dbAll("SELECT id FROM checklist_columns WHERE list_id = ? AND id <> ? ORDER BY sort_order ASC, id ASC", [listId, columnId]);
        const fallbackId = columns[0]?.id || null;
        await dbRun("UPDATE checklist_items SET column_id = ? WHERE list_id = ? AND column_id = ?", [fallbackId, listId, columnId]);
        await dbRun("DELETE FROM checklist_columns WHERE id = ? AND list_id = ?", [columnId, listId]);
        res.json({ success: true, fallbackColumnId: fallbackId ? Number(fallbackId) : null });
    } catch (e) {
        res.status(500).json({ error: 'Failed to delete checklist column' });
    }
});

app.get('/api/checklists/:id/items', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    if (!Number.isFinite(listId)) return res.status(400).json({ error: 'Invalid checklist id' });
    try {
        const access = await getChecklistAccess(listId, req.user.username);
        if (!access) return res.status(404).json({ error: '清单不存在或无权限' });
        const rows = await dbAll(
            "SELECT id, list_id, column_id, title, completed, completed_by, notes, subtasks_json, created_at, updated_at FROM checklist_items WHERE list_id = ? ORDER BY created_at ASC",
            [listId]
        );
        res.json({ items: rows.map(mapChecklistItemRow) });
    } catch (e) {
        res.status(500).json({ error: 'Failed to load checklist items' });
    }
});

app.post('/api/checklists/:id/items', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    if (!Number.isFinite(listId)) return res.status(400).json({ error: 'Invalid checklist id' });
    const title = String(req.body.title || '').trim();
    if (!title) return res.status(400).json({ error: 'Title is required' });
    const subtasks = normalizeChecklistSubtasks(req.body.subtasks);
    const notes = typeof req.body.notes === 'string' ? req.body.notes.trim() : '';
    const columnId = req.body.columnId === null || req.body.columnId === undefined
        ? null
        : parseInt(req.body.columnId, 10);
    const now = Date.now();
    try {
        const access = await getChecklistAccess(listId, req.user.username);
        if (!access) return res.status(404).json({ error: '清单不存在或无权限' });
        if (!access.canEdit) return res.status(403).json({ error: '无权编辑该清单' });
        let targetColumnId = Number.isFinite(columnId) ? columnId : null;
        if (targetColumnId !== null) {
            const cols = await dbAll("SELECT id FROM checklist_columns WHERE id = ? AND list_id = ?", [targetColumnId, listId]);
            if (!cols.length) targetColumnId = null;
        }
        if (targetColumnId === null) {
            const cols = await dbAll("SELECT id FROM checklist_columns WHERE list_id = ? ORDER BY sort_order ASC, id ASC LIMIT 1", [listId]);
            if (cols.length) targetColumnId = cols[0].id;
        }
        const allSubtasksDone = subtasks.length ? subtasks.every(s => s.completed) : false;
        const result = await dbRun(
            "INSERT INTO checklist_items (list_id, owner, column_id, title, completed, completed_by, notes, subtasks_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                listId,
                access.list.owner,
                targetColumnId,
                title,
                allSubtasksDone ? 1 : 0,
                allSubtasksDone ? req.user.username : null,
                notes,
                JSON.stringify(subtasks),
                now,
                now
            ]
        );
        res.json({
            success: true,
            item: {
                id: result.lastID,
                listId,
                columnId: targetColumnId,
                title,
                completed: allSubtasksDone,
                completedBy: allSubtasksDone ? req.user.username : '',
                notes,
                subtasks,
                createdAt: now,
                updatedAt: now
            }
        });
    } catch (e) {
        res.status(500).json({ error: 'Failed to create checklist item' });
    }
});

app.patch('/api/checklists/:id/items/:itemId', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    const itemId = parseInt(req.params.itemId, 10);
    if (!Number.isFinite(listId) || !Number.isFinite(itemId)) return res.status(400).json({ error: 'Invalid id' });
    const title = typeof req.body.title === 'string' ? req.body.title.trim() : undefined;
    const completed = typeof req.body.completed === 'boolean' ? req.body.completed : undefined;
    const subtasks = req.body.subtasks !== undefined ? normalizeChecklistSubtasks(req.body.subtasks) : undefined;
    const notes = typeof req.body.notes === 'string' ? req.body.notes.trim() : undefined;
    const columnId = req.body.columnId === null || req.body.columnId === undefined
        ? undefined
        : parseInt(req.body.columnId, 10);
    if (title === undefined && completed === undefined && columnId === undefined && subtasks === undefined && notes === undefined) {
        return res.status(400).json({ error: 'No changes' });
    }
    const now = Date.now();
    try {
        const access = await getChecklistAccess(listId, req.user.username);
        if (!access) return res.status(404).json({ error: '清单不存在或无权限' });
    const editingTitle = title !== undefined;
    if ((editingTitle || notes !== undefined) && !access.canEdit) return res.status(403).json({ error: '无权编辑该清单' });
        const rows = await dbAll(
            "SELECT id, list_id, column_id, title, completed, completed_by, notes, subtasks_json, created_at, updated_at FROM checklist_items WHERE id = ? AND list_id = ?",
            [itemId, listId]
        );
        const current = rows[0];
        if (!current) return res.status(404).json({ error: 'Item not found' });
        const nextTitle = title !== undefined ? title : current.title;
        const nextNotes = notes !== undefined ? notes : (current.notes || '');
        let nextSubtasks = subtasks !== undefined ? subtasks : parseChecklistSubtasks(current.subtasks_json);
        let nextCompleted = completed !== undefined ? (completed ? 1 : 0) : current.completed;
        let nextCompletedBy = completed !== undefined
            ? (completed ? req.user.username : null)
            : current.completed_by || null;
        let nextColumnId = current.column_id;
        if (completed !== undefined && nextSubtasks.length) {
            nextSubtasks = nextSubtasks.map(s => ({ ...s, completed: !!completed }));
        } else if (subtasks !== undefined && completed === undefined && nextSubtasks.length) {
            const allDone = nextSubtasks.every(s => s.completed);
            nextCompleted = allDone ? 1 : 0;
            nextCompletedBy = allDone ? req.user.username : null;
        }
        if (columnId !== undefined) {
            if (Number.isFinite(columnId)) {
                const cols = await dbAll("SELECT id FROM checklist_columns WHERE id = ? AND list_id = ?", [columnId, listId]);
                if (cols.length) nextColumnId = columnId;
            } else {
                nextColumnId = null;
            }
        }
        await dbRun(
            "UPDATE checklist_items SET title = ?, completed = ?, completed_by = ?, column_id = ?, notes = ?, subtasks_json = ?, updated_at = ? WHERE id = ? AND list_id = ?",
            [nextTitle, nextCompleted, nextCompletedBy, nextColumnId, nextNotes, JSON.stringify(nextSubtasks), now, itemId, listId]
        );
        res.json({
            success: true,
            item: {
                id: itemId,
                listId,
                columnId: nextColumnId === null ? null : Number(nextColumnId),
                title: nextTitle,
                completed: !!nextCompleted,
                completedBy: nextCompletedBy || '',
                notes: nextNotes,
                subtasks: nextSubtasks,
                createdAt: current.created_at,
                updatedAt: now
            }
        });
    } catch (e) {
        res.status(500).json({ error: 'Failed to update item' });
    }
});

app.delete('/api/checklists/:id/items/:itemId', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    const itemId = parseInt(req.params.itemId, 10);
    if (!Number.isFinite(listId) || !Number.isFinite(itemId)) return res.status(400).json({ error: 'Invalid id' });
    try {
        const access = await getChecklistAccess(listId, req.user.username);
        if (!access) return res.status(404).json({ error: '清单不存在或无权限' });
        if (!access.canEdit) return res.status(403).json({ error: '无权删除该清单的条目' });
        const rows = await dbAll(
            "SELECT id FROM checklist_items WHERE id = ? AND list_id = ?",
            [itemId, listId]
        );
        if (!rows.length) return res.status(404).json({ error: 'Item not found' });
        await dbRun("DELETE FROM checklist_items WHERE id = ? AND list_id = ?", [itemId, listId]);
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: 'Failed to delete item' });
    }
});

app.get('/api/checklists/:id/shares', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    if (!Number.isFinite(listId)) return res.status(400).json({ error: 'Invalid checklist id' });
    try {
        const owned = await assertChecklistOwner(listId, req.user.username);
        if (owned) {
            const rows = await dbAll(
                "SELECT shared_user, can_edit, created_at FROM checklist_shares WHERE list_id = ? ORDER BY created_at ASC",
                [listId]
            );
            return res.json({
                owner: owned.owner,
                shared: rows.map(r => ({
                    user: r.shared_user,
                    canEdit: !!r.can_edit,
                    createdAt: r.created_at
                }))
            });
        }
        const access = await getChecklistAccess(listId, req.user.username);
        if (!access) return res.status(404).json({ error: '清单不存在或无权限' });
        if (access.role !== 'shared') return res.json({ owner: access.list.owner, shared: [], readonly: true });
        return res.json({
            owner: access.list.owner,
            readonly: true,
            shared: [{
                user: req.user.username,
                canEdit: !!access.canEdit,
                createdAt: access.list.created_at
            }]
        });
    } catch (e) {
        res.status(500).json({ error: 'Failed to load shares' });
    }
});

app.post('/api/checklists/:id/shares', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    if (!Number.isFinite(listId)) return res.status(400).json({ error: 'Invalid checklist id' });
    const sharedUser = String(req.body.user || '').trim();
    if (!sharedUser) return res.status(400).json({ error: 'User is required' });
    const canEdit = typeof req.body.canEdit === 'boolean' ? req.body.canEdit : true;
    const now = Date.now();
    try {
        const owned = await assertChecklistOwner(listId, req.user.username);
        if (!owned) return res.status(404).json({ error: '清单不存在或无权限' });
        if (sharedUser === req.user.username) return res.status(400).json({ error: '不能分享给自己' });
        const userRows = await dbAll("SELECT username FROM users WHERE username = ?", [sharedUser]);
        if (!userRows.length) return res.status(404).json({ error: '用户不存在' });
        await dbRun(
            "INSERT OR REPLACE INTO checklist_shares (list_id, owner, shared_user, can_edit, created_at) VALUES (?, ?, ?, ?, ?)",
            [listId, req.user.username, sharedUser, canEdit ? 1 : 0, now]
        );
        res.json({ success: true, user: sharedUser, canEdit, createdAt: now });
    } catch (e) {
        res.status(500).json({ error: 'Failed to share checklist' });
    }
});

app.patch('/api/checklists/:id/shares/:user', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    if (!Number.isFinite(listId)) return res.status(400).json({ error: 'Invalid checklist id' });
    const user = String(req.params.user || '').trim();
    if (!user) return res.status(400).json({ error: 'Invalid user' });
    const canEdit = typeof req.body.canEdit === 'boolean' ? req.body.canEdit : undefined;
    if (canEdit === undefined) return res.status(400).json({ error: 'No changes' });
    try {
        const owned = await assertChecklistOwner(listId, req.user.username);
        if (!owned) return res.status(404).json({ error: '清单不存在或无权限' });
        const rows = await dbAll("SELECT id, can_edit FROM checklist_shares WHERE list_id = ? AND shared_user = ?", [listId, user]);
        const share = rows[0];
        if (!share) return res.status(404).json({ error: '共享用户不存在' });
        const nextEdit = canEdit === undefined ? share.can_edit : (canEdit ? 1 : 0);
        await dbRun("UPDATE checklist_shares SET can_edit = ? WHERE list_id = ? AND shared_user = ?", [nextEdit, listId, user]);
        res.json({ success: true, user, canEdit: !!nextEdit });
    } catch (e) {
        res.status(500).json({ error: 'Failed to update share' });
    }
});

app.delete('/api/checklists/:id/shares/:user', authenticate, async (req, res) => {
    const listId = parseInt(req.params.id, 10);
    if (!Number.isFinite(listId)) return res.status(400).json({ error: 'Invalid checklist id' });
    const user = String(req.params.user || '').trim();
    if (!user) return res.status(400).json({ error: 'Invalid user' });
    try {
        const owned = await assertChecklistOwner(listId, req.user.username);
        if (!owned) return res.status(404).json({ error: '清单不存在或无权限' });
        await dbRun("DELETE FROM checklist_shares WHERE list_id = ? AND shared_user = ?", [listId, user]);
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: 'Failed to remove share' });
    }
});

// Attachments
app.post('/api/tasks/:taskId/attachments', authenticate, (req, res) => {
    attachmentUpload.single('file')(req, res, async (err) => {
        if (err) return res.status(400).json({ error: err.message || 'Upload failed' });
        if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

        const taskId = parseInt(req.params.taskId, 10);
        if (!Number.isFinite(taskId)) {
            fs.unlink(req.file.path, () => {});
            return res.status(400).json({ error: 'Invalid task id' });
        }

        const originalName = normalizeOriginalName(req.file.originalname);
        const mimeType = req.file.mimetype || 'application/octet-stream';
        const size = req.file.size || 0;
        const attachmentId = req.attachmentId;
        const attachmentExt = req.attachmentExt || '';

        try {
            const row = await dbAll("SELECT json_data, version FROM data WHERE username = ?", [req.user.username]);
            const dataRow = row[0];
            const tasks = dataRow && dataRow.json_data ? JSON.parse(dataRow.json_data) : [];
            const task = tasks.find((t) => t && Number(t.id) === taskId);
            if (!task) {
                fs.unlink(req.file.path, () => {});
                return res.status(404).json({ error: 'Task not found' });
            }

            const stored = await storeAttachmentFile({
                tmpPath: req.file.path,
                id: attachmentId,
                ext: attachmentExt,
                mimeType,
                originalName,
                size
            });

            const createdAt = Date.now();
            const attachmentMeta = {
                id: attachmentId,
                name: originalName,
                mime: mimeType,
                size,
                createdAt
            };
            if (!Array.isArray(task.attachments)) task.attachments = [];
            task.attachments.push(attachmentMeta);

            const newVersion = Date.now();
            await dbRun('BEGIN');
            await dbRun(
                `INSERT INTO attachments
                (id, owner_user_id, task_id, original_name, mime_type, size, storage_driver, storage_path, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [
                    attachmentId,
                    req.user.username,
                    taskId,
                    originalName,
                    mimeType,
                    size,
                    stored.storageDriver,
                    stored.storagePath,
                    createdAt
                ]
            );
            await dbRun(
                "INSERT OR REPLACE INTO data (username, json_data, version) VALUES (?, ?, ?)",
                [req.user.username, JSON.stringify(tasks), newVersion]
            );
            await dbRun('COMMIT');

            return res.json({ success: true, attachment: attachmentMeta, version: newVersion });
        } catch (e) {
            try { await dbRun('ROLLBACK'); } catch (rollbackErr) {}
            if (req.file?.path) fs.unlink(req.file.path, () => {});
            return res.status(500).json({ error: 'Attachment upload failed' });
        }
    });
});

app.delete('/api/tasks/:taskId/attachments/:attachmentId', authenticate, async (req, res) => {
    const taskId = parseInt(req.params.taskId, 10);
    if (!Number.isFinite(taskId)) return res.status(400).json({ error: 'Invalid task id' });
    const attachmentId = String(req.params.attachmentId || '').trim();
    if (!attachmentId) return res.status(400).json({ error: 'Invalid attachment id' });

    try {
        const rows = await dbAll(
            "SELECT id, owner_user_id, task_id, storage_driver, storage_path, original_name, mime_type, size FROM attachments WHERE id = ? AND owner_user_id = ?",
            [attachmentId, req.user.username]
        );
        const attachment = rows[0];
        if (!attachment || Number(attachment.task_id) !== taskId) {
            return res.status(404).json({ error: 'Attachment not found' });
        }

        const dataRows = await dbAll("SELECT json_data FROM data WHERE username = ?", [req.user.username]);
        const tasks = dataRows[0] && dataRows[0].json_data ? JSON.parse(dataRows[0].json_data) : [];
        const task = tasks.find((t) => t && Number(t.id) === taskId);
        if (!task) return res.status(404).json({ error: 'Task not found' });

        if (Array.isArray(task.attachments)) {
            task.attachments = task.attachments.filter((a) => a && a.id !== attachmentId);
        }

        const newVersion = Date.now();
        await dbRun('BEGIN');
        await dbRun("DELETE FROM attachments WHERE id = ? AND owner_user_id = ?", [attachmentId, req.user.username]);
        await dbRun(
            "INSERT OR REPLACE INTO data (username, json_data, version) VALUES (?, ?, ?)",
            [req.user.username, JSON.stringify(tasks), newVersion]
        );
        await dbRun('COMMIT');

        try {
            await deleteAttachmentFile({
                storageDriver: attachment.storage_driver,
                storagePath: attachment.storage_path
            });
        } catch (e) {
            console.warn('delete attachment file failed', e);
        }

        return res.json({ success: true, version: newVersion });
    } catch (e) {
        try { await dbRun('ROLLBACK'); } catch (rollbackErr) {}
        return res.status(500).json({ error: 'Failed to delete attachment' });
    }
});

app.get('/api/attachments/:attachmentId/download', authenticate, async (req, res) => {
    const attachmentId = String(req.params.attachmentId || '').trim();
    if (!attachmentId) return res.status(400).json({ error: 'Invalid attachment id' });

    try {
        const rows = await dbAll(
            "SELECT id, owner_user_id, original_name, mime_type, size, storage_driver, storage_path FROM attachments WHERE id = ? AND owner_user_id = ?",
            [attachmentId, req.user.username]
        );
        const attachment = rows[0];
        if (!attachment) return res.status(404).json({ error: 'Attachment not found' });

        const safeName = normalizeOriginalName(attachment.original_name);
        res.setHeader('Content-Disposition', buildDownloadDisposition(safeName));
        res.setHeader('Content-Type', attachment.mime_type || 'application/octet-stream');

        if (attachment.storage_driver === 'local') {
            const absPath = path.join(ATTACHMENTS_DIR, attachment.storage_path);
            if (!fs.existsSync(absPath)) return res.status(404).json({ error: 'File missing' });
            return res.sendFile(absPath);
        }

        if (!ATTACHMENTS_S3_BUCKET) return res.status(500).json({ error: 'Storage not configured' });
        const result = await s3Client.send(new GetObjectCommand({
            Bucket: ATTACHMENTS_S3_BUCKET,
            Key: attachment.storage_path
        }));
        if (result.ContentLength) res.setHeader('Content-Length', result.ContentLength);
        await streamPipeline(result.Body, res);
    } catch (e) {
        return res.status(500).json({ error: 'Failed to download attachment' });
    }
});

// User settings
app.get('/api/user/settings', authenticate, async (req, res) => {
    try {
        const rows = await dbAll("SELECT settings_json FROM user_settings WHERE username = ?", [req.user.username]);
        if (!rows.length || !rows[0].settings_json) return res.json({ settings: getUserSettingsDefaults() });
        let parsed = null;
        try {
            parsed = JSON.parse(rows[0].settings_json);
        } catch (e) {
            parsed = null;
        }
        return res.json({ settings: sanitizeUserSettings(parsed || {}) });
    } catch (e) {
        return res.status(500).json({ error: 'Failed to load user settings' });
    }
});

app.post('/api/user/settings', authenticate, async (req, res) => {
    const raw = req.body && typeof req.body === 'object' ? (req.body.settings || req.body) : null;
    if (!raw || typeof raw !== 'object') return res.status(400).json({ error: 'Invalid settings' });
    const settings = sanitizeUserSettings(raw);
    try {
        await dbRun(
            "INSERT OR REPLACE INTO user_settings (username, settings_json, updated_at) VALUES (?, ?, ?)",
            [req.user.username, JSON.stringify(settings), Date.now()]
        );
        return res.json({ success: true, settings });
    } catch (e) {
        return res.status(500).json({ error: 'Failed to save user settings' });
    }
});

// Data export/import & dangerous ops (v2)
app.get('/api/v2/export', authenticate, async (req, res) => {
    const username = req.user.username;
    try {
        const tasksRows = await dbAll("SELECT * FROM tasks_v2 WHERE username = ? ORDER BY updated_at DESC", [username]);
        const tasks = tasksRows.map((row) => ({
            id: row.id,
            title: row.title || '',
            notes: row.notes || '',
            status: row.status || 'todo',
            dueDate: row.due_date || '',
            startTime: row.start_time || '',
            endDate: row.end_date || '',
            endTime: row.end_time || '',
            tags: parseJsonArray(row.tags_json),
            inbox: !!row.inbox,
            priority: Number(row.priority || 0),
            remindAt: row.remind_at,
            repeatRule: row.repeat_rule || '',
            attachments: normalizeTaskAttachments(row.attachments_json),
            subtasks: normalizeTaskSubtasks(row.subtasks_json),
            createdAt: row.created_at,
            updatedAt: row.updated_at,
            deletedAt: row.deleted_at
        }));

        const checklistRows = await dbAll(
            "SELECT id, name, owner, created_at, updated_at FROM checklists WHERE owner = ? ORDER BY id ASC",
            [username]
        );
        const checklists = checklistRows.map((row) => ({
            id: Number(row.id),
            name: row.name || '',
            owner: row.owner || username,
            sharedCount: 0,
            createdAt: row.created_at,
            updatedAt: row.updated_at
        }));
        const listIds = checklistRows.map((r) => Number(r.id)).filter((id) => Number.isFinite(id) && id > 0);

        const checklistItemsRows = await dbAll(
            "SELECT id, list_id, column_id, title, completed, completed_by, notes, subtasks_json, created_at, updated_at FROM checklist_items WHERE owner = ? ORDER BY id ASC",
            [username]
        );
        const checklistItems = checklistItemsRows.map(mapChecklistItemRow);

        let checklistColumns = [];
        if (listIds.length) {
            const placeholders = listIds.map(() => '?').join(',');
            checklistColumns = await dbAll(
                `SELECT id, list_id, name, sort_order, created_at, updated_at FROM checklist_columns WHERE list_id IN (${placeholders}) ORDER BY list_id ASC, sort_order ASC, id ASC`,
                listIds
            );
            checklistColumns = checklistColumns.map((row) => ({
                id: Number(row.id),
                listId: Number(row.list_id),
                name: row.name || '',
                sortOrder: Number(row.sort_order || 0),
                createdAt: row.created_at,
                updatedAt: row.updated_at
            }));
        }

        const checklistSharesRows = await dbAll(
            "SELECT list_id, shared_user, can_edit, created_at FROM checklist_shares WHERE owner = ? ORDER BY created_at ASC",
            [username]
        );
        const checklistShares = checklistSharesRows.map((row) => ({
            listId: Number(row.list_id),
            sharedUser: row.shared_user || '',
            canEdit: !!row.can_edit,
            createdAt: row.created_at
        }));

        const activityRows = await dbAll("SELECT * FROM time_activities WHERE username = ? ORDER BY updated_at DESC", [username]);
        const activities = activityRows.map((row) => ({
            id: row.id,
            name: row.name || '',
            taskId: row.task_id || null,
            icon: row.icon || '',
            color: row.color || '',
            category: row.category || '',
            goal: row.goal || '',
            note: row.note || '',
            createdAt: row.created_at,
            updatedAt: row.updated_at,
            deletedAt: row.deleted_at
        }));
        const entryRows = await dbAll("SELECT * FROM time_entries WHERE username = ? ORDER BY started_at DESC", [username]);
        const entries = entryRows.map((row) => ({
            id: row.id,
            activityId: row.activity_id,
            taskId: row.task_id || null,
            startedAt: row.started_at,
            endedAt: row.ended_at,
            durationMs: row.duration_ms,
            note: row.note || '',
            tags: parseJsonArray(row.tags_json),
            createdAt: row.created_at,
            updatedAt: row.updated_at,
            deletedAt: row.deleted_at
        }));

        const settingsRow = await dbAll("SELECT settings_json FROM user_settings WHERE username = ?", [username]);
        let userSettings = getUserSettingsDefaults();
        if (settingsRow.length && settingsRow[0].settings_json) {
            try {
                userSettings = sanitizeUserSettings(JSON.parse(settingsRow[0].settings_json));
            } catch (e) {}
        }

        const pomodoroSettingsRow = await dbAll(
            "SELECT work_min, short_break_min, long_break_min, long_break_every, auto_start_next, auto_start_break, auto_start_work, auto_finish_task, updated_at FROM pomodoro_settings WHERE username = ?",
            [username]
        );
        const pomodoroSettings = pomodoroSettingsRow.length
            ? {
                workMin: pomodoroSettingsRow[0].work_min,
                shortBreakMin: pomodoroSettingsRow[0].short_break_min,
                longBreakMin: pomodoroSettingsRow[0].long_break_min,
                longBreakEvery: pomodoroSettingsRow[0].long_break_every,
                autoStartNext: !!pomodoroSettingsRow[0].auto_start_next,
                autoStartBreak: !!pomodoroSettingsRow[0].auto_start_break,
                autoStartWork: !!pomodoroSettingsRow[0].auto_start_work,
                autoFinishTask: !!pomodoroSettingsRow[0].auto_finish_task,
                updatedAt: pomodoroSettingsRow[0].updated_at
            }
            : null;

        const pomodoroStateRow = await dbAll(
            "SELECT mode, remaining_ms, is_running, target_end, cycle_count, current_task_id, updated_at FROM pomodoro_state WHERE username = ?",
            [username]
        );
        const pomodoroState = pomodoroStateRow.length
            ? {
                mode: pomodoroStateRow[0].mode,
                remainingMs: pomodoroStateRow[0].remaining_ms,
                isRunning: !!pomodoroStateRow[0].is_running,
                targetEnd: pomodoroStateRow[0].target_end,
                cycleCount: pomodoroStateRow[0].cycle_count,
                currentTaskId: pomodoroStateRow[0].current_task_id,
                updatedAt: pomodoroStateRow[0].updated_at
            }
            : null;

        const pomodoroSessions = await dbAll(
            "SELECT id, task_id, task_title, started_at, ended_at, duration_min, created_at FROM pomodoro_sessions WHERE username = ? ORDER BY ended_at DESC",
            [username]
        );
        const pomodoroDaily = await dbAll(
            "SELECT date_key, work_sessions, work_minutes, break_minutes, updated_at FROM pomodoro_daily_stats WHERE username = ? ORDER BY date_key DESC",
            [username]
        );

        return res.json({
            exportedAt: Date.now(),
            data: {
                settings: userSettings,
                tasks,
                checklists: {
                    lists: checklists,
                    columns: checklistColumns,
                    items: checklistItems,
                    shares: checklistShares
                },
                timeTracking: {
                    activities,
                    entries
                },
                pomodoro: {
                    settings: pomodoroSettings,
                    state: pomodoroState,
                    sessions: pomodoroSessions,
                    dailyStats: pomodoroDaily
                }
            }
        });
    } catch (e) {
        return res.status(500).json({ error: 'Failed to export data' });
    }
});

app.post('/api/v2/import', authenticate, async (req, res) => {
    const username = req.user.username;
    const mode = req.body && typeof req.body.mode === 'string' ? req.body.mode : 'merge';
    const payload = req.body && typeof req.body === 'object' ? (req.body.data || req.body.payload || req.body) : null;
    if (!payload || typeof payload !== 'object') return res.status(400).json({ error: 'Invalid import payload' });
    if (mode !== 'merge' && mode !== 'overwrite') return res.status(400).json({ error: 'Invalid import mode' });

    const data = payload.data && typeof payload.data === 'object' ? payload.data : payload;
    const now = Date.now();

    const clearUserData = async () => {
        await dbRun("DELETE FROM tasks_v2 WHERE username = ?", [username]);
        await dbRun("DELETE FROM time_entries WHERE username = ?", [username]);
        await dbRun("DELETE FROM time_activities WHERE username = ?", [username]);
        await dbRun("DELETE FROM pomodoro_sessions WHERE username = ?", [username]);
        await dbRun("DELETE FROM pomodoro_daily_stats WHERE username = ?", [username]);
        await dbRun("DELETE FROM pomodoro_state WHERE username = ?", [username]);
        await dbRun("DELETE FROM pomodoro_settings WHERE username = ?", [username]);
        await dbRun("DELETE FROM user_settings WHERE username = ?", [username]);

        const listRows = await dbAll("SELECT id FROM checklists WHERE owner = ?", [username]);
        const listIds = listRows.map((r) => Number(r.id)).filter((id) => Number.isFinite(id) && id > 0);
        for (const listId of listIds) {
            await dbRun("DELETE FROM checklist_shares WHERE list_id = ?", [listId]);
            await dbRun("DELETE FROM checklist_columns WHERE list_id = ?", [listId]);
            await dbRun("DELETE FROM checklist_items WHERE list_id = ?", [listId]);
        }
        await dbRun("DELETE FROM checklists WHERE owner = ?", [username]);
    };

    const importSettings = async () => {
        if (!data.settings || typeof data.settings !== 'object') return;
        const sanitized = sanitizeUserSettings(data.settings);
        await dbRun(
            "INSERT OR REPLACE INTO user_settings (username, settings_json, updated_at) VALUES (?, ?, ?)",
            [username, JSON.stringify(sanitized), now]
        );
    };

    const importTasks = async () => {
        const tasks = Array.isArray(data.tasks) ? data.tasks : [];
        for (const t of tasks) {
            const id = String(t?.id || '').trim();
            const title = String(t?.title || '').trim();
            if (!id || !title) continue;
            const notes = String(t?.notes || '').trim();
            const status = normalizeStatus(t?.status);
            const dueDate = normalizeDateKey(t?.dueDate ?? t?.due_date);
            const startTime = String(t?.startTime ?? t?.start_time ?? '').trim();
            let endDate = normalizeDateKey(t?.endDate ?? t?.end_date);
            let endTime = String(t?.endTime ?? t?.end_time ?? '').trim();
            const tags = normalizeTags(t?.tags);
            const subtasks = normalizeTaskSubtasks(t?.subtasks);
            const attachments = normalizeTaskAttachments(t?.attachments);
            const inbox = parseBool(t?.inbox) ? 1 : 0;
            const priority = Math.max(0, parseIntSafe(t?.priority) ?? 0);
            const remindAt = parseIntSafe(t?.remindAt ?? t?.remind_at);
            const repeatRule = String(t?.repeatRule ?? t?.repeat_rule ?? '').trim();
            const createdAt = parseIntSafe(t?.createdAt ?? t?.created_at) ?? now;
            const updatedAt = parseIntSafe(t?.updatedAt ?? t?.updated_at) ?? now;
            const deletedAt = parseIntSafe(t?.deletedAt ?? t?.deleted_at);

            if (endTime.includes('+')) {
                const plusIndex = endTime.lastIndexOf('+');
                const rawOffset = parseIntSafe(endTime.substring(plusIndex + 1).trim()) ?? 0;
                const offsetDays = Math.max(0, rawOffset);
                const timePart = endTime.substring(0, plusIndex).trim();
                endTime = timePart;
                if (timePart === '24:00') {
                    endTime = '00:00';
                    if (dueDate) {
                        endDate = toUtcDateKey(utcDayStartMs(Date.parse(`${dueDate}T00:00:00Z`) + DAY_MS * (offsetDays + 1)));
                    }
                } else if (dueDate && offsetDays > 0) {
                    endDate = toUtcDateKey(utcDayStartMs(Date.parse(`${dueDate}T00:00:00Z`) + DAY_MS * offsetDays));
                }
            } else if (endTime === '24:00') {
                endTime = '00:00';
                if (dueDate) {
                    endDate = toUtcDateKey(utcDayStartMs(Date.parse(`${dueDate}T00:00:00Z`) + DAY_MS));
                }
            }
            if (!endDate && dueDate && endTime) {
                endDate = dueDate;
                if (startTime && endTime <= startTime) {
                    endDate = toUtcDateKey(utcDayStartMs(Date.parse(`${dueDate}T00:00:00Z`) + DAY_MS));
                }
            }
            if (dueDate && endDate && endDate < dueDate) {
                endDate = dueDate;
            }
            await dbRun(
                `INSERT OR REPLACE INTO tasks_v2
                (id, username, title, notes, status, due_date, start_time, end_date, end_time, tags_json, subtasks_json, attachments_json, inbox, priority, remind_at, repeat_rule, created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [
                    id,
                    username,
                    title,
                    notes,
                    status,
                    dueDate || null,
                    startTime || null,
                    endDate || null,
                    endTime || null,
                    JSON.stringify(tags),
                    JSON.stringify(subtasks),
                    JSON.stringify(attachments),
                    inbox,
                    priority,
                    remindAt,
                    repeatRule || null,
                    createdAt,
                    updatedAt,
                    deletedAt ?? null
                ]
            );
        }
    };

    const importChecklists = async () => {
        const lists = Array.isArray(data?.checklists?.lists) ? data.checklists.lists : [];
        const columns = Array.isArray(data?.checklists?.columns) ? data.checklists.columns : [];
        const items = Array.isArray(data?.checklists?.items) ? data.checklists.items : [];
        const shares = Array.isArray(data?.checklists?.shares) ? data.checklists.shares : [];

        for (const list of lists) {
            const id = parseIntSafe(list?.id);
            const name = String(list?.name || '').trim();
            if (!Number.isFinite(id) || id <= 0 || !name) continue;
            const createdAt = parseIntSafe(list?.createdAt ?? list?.created_at) ?? now;
            const updatedAt = parseIntSafe(list?.updatedAt ?? list?.updated_at) ?? now;
            await dbRun(
                "INSERT OR REPLACE INTO checklists (id, owner, name, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                [id, username, name, createdAt, updatedAt]
            );
        }

        for (const col of columns) {
            const id = parseIntSafe(col?.id);
            const listId = parseIntSafe(col?.listId ?? col?.list_id);
            const name = String(col?.name || '').trim();
            const sortOrder = parseIntSafe(col?.sortOrder ?? col?.sort_order) ?? 0;
            if (!Number.isFinite(id) || id <= 0 || !Number.isFinite(listId) || listId <= 0 || !name) continue;
            const createdAt = parseIntSafe(col?.createdAt ?? col?.created_at) ?? now;
            const updatedAt = parseIntSafe(col?.updatedAt ?? col?.updated_at) ?? now;
            await dbRun(
                "INSERT OR REPLACE INTO checklist_columns (id, list_id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                [id, listId, name, sortOrder, createdAt, updatedAt]
            );
        }

        for (const item of items) {
            const id = parseIntSafe(item?.id);
            const listId = parseIntSafe(item?.listId ?? item?.list_id);
            const columnIdRaw = parseIntSafe(item?.columnId ?? item?.column_id);
            const columnId = Number.isFinite(columnIdRaw) ? columnIdRaw : null;
            const title = String(item?.title || '').trim();
            if (!Number.isFinite(id) || id <= 0 || !Number.isFinite(listId) || listId <= 0 || !title) continue;
            const completed = item?.completed ? 1 : 0;
            const completedBy = String(item?.completedBy ?? item?.completed_by ?? '').trim();
            const notes = String(item?.notes || '').trim();
            const subtasks = normalizeChecklistSubtasks(item?.subtasks);
            const createdAt = parseIntSafe(item?.createdAt ?? item?.created_at) ?? now;
            const updatedAt = parseIntSafe(item?.updatedAt ?? item?.updated_at) ?? now;
            await dbRun(
                `INSERT OR REPLACE INTO checklist_items
                (id, list_id, owner, column_id, title, completed, completed_by, subtasks_json, notes, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [id, listId, username, columnId, title, completed, completedBy || null, JSON.stringify(subtasks), notes, createdAt, updatedAt]
            );
        }

        for (const share of shares) {
            const listId = parseIntSafe(share?.listId ?? share?.list_id);
            const sharedUser = String(share?.sharedUser ?? share?.shared_user ?? '').trim();
            if (!Number.isFinite(listId) || listId <= 0 || !sharedUser) continue;
            const canEdit = share?.canEdit ? 1 : 0;
            const createdAt = parseIntSafe(share?.createdAt ?? share?.created_at) ?? now;
            await dbRun(
                "INSERT OR REPLACE INTO checklist_shares (list_id, owner, shared_user, can_edit, created_at) VALUES (?, ?, ?, ?, ?)",
                [listId, username, sharedUser, canEdit, createdAt]
            );
        }
    };

    const importTimeTracking = async () => {
        const activities = Array.isArray(data?.timeTracking?.activities) ? data.timeTracking.activities : [];
        const entries = Array.isArray(data?.timeTracking?.entries) ? data.timeTracking.entries : [];

        for (const a of activities) {
            const id = String(a?.id || '').trim();
            const name = String(a?.name || '').trim();
            if (!id || !name) continue;
            const taskId = a?.taskId ?? a?.task_id ?? null;
            const icon = String(a?.icon || '').trim();
            const color = String(a?.color || '').trim();
            const category = String(a?.category || '').trim();
            const goal = String(a?.goal || '').trim();
            const note = typeof a?.note === 'string' ? a.note : (a?.note == null ? '' : String(a.note));
            const createdAt = parseIntSafe(a?.createdAt ?? a?.created_at) ?? now;
            const updatedAt = parseIntSafe(a?.updatedAt ?? a?.updated_at) ?? now;
            const deletedAt = parseIntSafe(a?.deletedAt ?? a?.deleted_at);
            await dbRun(
                `INSERT OR REPLACE INTO time_activities
                (id, username, task_id, name, icon, color, category, goal, note, created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [id, username, taskId, name, icon, color, category, goal, note, createdAt, updatedAt, deletedAt ?? null]
            );
        }

        for (const e of entries) {
            const id = String(e?.id || '').trim();
            const activityId = String(e?.activityId ?? e?.activity_id ?? '').trim();
            if (!id || !activityId) continue;
            const taskId = e?.taskId ?? e?.task_id ?? null;
            const startedAt = parseIntSafe(e?.startedAt ?? e?.started_at);
            if (!Number.isFinite(startedAt)) continue;
            const endedAt = parseIntSafe(e?.endedAt ?? e?.ended_at);
            const durationMs = parseIntSafe(e?.durationMs ?? e?.duration_ms);
            const note = String(e?.note || '').trim();
            const tags = normalizeTags(e?.tags);
            const createdAt = parseIntSafe(e?.createdAt ?? e?.created_at) ?? now;
            const updatedAt = parseIntSafe(e?.updatedAt ?? e?.updated_at) ?? now;
            const deletedAt = parseIntSafe(e?.deletedAt ?? e?.deleted_at);
            await dbRun(
                `INSERT OR REPLACE INTO time_entries
                (id, username, activity_id, task_id, started_at, ended_at, duration_ms, note, tags_json, created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [id, username, activityId, taskId, startedAt, endedAt ?? null, durationMs ?? null, note, JSON.stringify(tags), createdAt, updatedAt, deletedAt ?? null]
            );
        }
    };

    const importPomodoro = async () => {
        const settings = data?.pomodoro?.settings;
        const state = data?.pomodoro?.state;
        const sessions = Array.isArray(data?.pomodoro?.sessions) ? data.pomodoro.sessions : [];
        const dailyStats = Array.isArray(data?.pomodoro?.dailyStats) ? data.pomodoro.dailyStats : [];

        if (settings && typeof settings === 'object') {
            const defaults = getPomodoroDefaults();
            const workMin = Math.max(1, parseInt(settings.workMin, 10) || defaults.workMin);
            const shortMin = Math.max(1, parseInt(settings.shortBreakMin, 10) || defaults.shortBreakMin);
            const longMin = Math.max(1, parseInt(settings.longBreakMin, 10) || defaults.longBreakMin);
            const longEvery = Math.max(1, parseInt(settings.longBreakEvery, 10) || defaults.longBreakEvery);
            const autoStartNext = settings.autoStartNext ? 1 : 0;
            const autoStartBreak = settings.autoStartBreak ? 1 : 0;
            const autoStartWork = settings.autoStartWork ? 1 : 0;
            const autoFinishTask = settings.autoFinishTask ? 1 : 0;
            const updatedAt = parseIntSafe(settings.updatedAt) ?? now;
            await dbRun(
                `INSERT OR REPLACE INTO pomodoro_settings
                (username, work_min, short_break_min, long_break_min, long_break_every, auto_start_next, auto_start_break, auto_start_work, auto_finish_task, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [username, workMin, shortMin, longMin, longEvery, autoStartNext, autoStartBreak, autoStartWork, autoFinishTask, updatedAt]
            );
        }

        if (state && typeof state === 'object') {
            const allowedModes = new Set(['work', 'short', 'long']);
            const mode = allowedModes.has(state.mode) ? state.mode : 'work';
            const remainingMs = Math.max(0, parseInt(state.remainingMs, 10) || 0);
            const isRunning = state.isRunning ? 1 : 0;
            const targetEndParsed = parseIntSafe(state.targetEnd);
            const targetEnd = Number.isFinite(targetEndParsed) ? targetEndParsed : null;
            const cycleCount = Math.max(0, parseInt(state.cycleCount, 10) || 0);
            const currentTaskParsed = parseIntSafe(state.currentTaskId);
            const currentTaskId = Number.isFinite(currentTaskParsed) ? currentTaskParsed : null;
            const updatedAt = parseIntSafe(state.updatedAt) ?? now;
            await dbRun(
                `INSERT OR REPLACE INTO pomodoro_state
                (username, mode, remaining_ms, is_running, target_end, cycle_count, current_task_id, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                [username, mode, remainingMs, isRunning, targetEnd, cycleCount, currentTaskId, updatedAt]
            );
        }

        for (const s of sessions) {
            const id = parseIntSafe(s?.id);
            if (!Number.isFinite(id) || id <= 0) continue;
            const taskIdParsed = parseIntSafe(s?.taskId ?? s?.task_id);
            const taskId = Number.isFinite(taskIdParsed) ? taskIdParsed : null;
            const taskTitle = s?.taskTitle ? String(s.taskTitle) : (s?.task_title ? String(s.task_title) : null);
            const startedAtParsed = parseIntSafe(s?.startedAt ?? s?.started_at);
            const startedAt = Number.isFinite(startedAtParsed) ? startedAtParsed : null;
            const endedAtParsed = parseIntSafe(s?.endedAt ?? s?.ended_at);
            const endedAt = Number.isFinite(endedAtParsed) ? endedAtParsed : now;
            const durationMin = Math.max(1, parseInt(s?.durationMin ?? s?.duration_min, 10) || 1);
            const createdAt = parseIntSafe(s?.createdAt ?? s?.created_at) ?? now;
            await dbRun(
                `INSERT OR REPLACE INTO pomodoro_sessions
                (id, username, task_id, task_title, started_at, ended_at, duration_min, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                [id, username, taskId, taskTitle, startedAt, endedAt, durationMin, createdAt]
            );
        }

        for (const d of dailyStats) {
            const dateKey = String(d?.date_key || d?.dateKey || '').trim();
            if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) continue;
            const workSessions = Math.max(0, parseInt(d?.work_sessions ?? d?.workSessions, 10) || 0);
            const workMinutes = Math.max(0, parseInt(d?.work_minutes ?? d?.workMinutes, 10) || 0);
            const breakMinutes = Math.max(0, parseInt(d?.break_minutes ?? d?.breakMinutes, 10) || 0);
            const updatedAt = parseIntSafe(d?.updated_at ?? d?.updatedAt) ?? now;
            await dbRun(
                `INSERT OR REPLACE INTO pomodoro_daily_stats
                (username, date_key, work_sessions, work_minutes, break_minutes, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)`,
                [username, dateKey, workSessions, workMinutes, breakMinutes, updatedAt]
            );
        }
    };

    try {
        await dbRun('BEGIN TRANSACTION');
        if (mode === 'overwrite') {
            await clearUserData();
        }
        await importSettings();
        await importTasks();
        await importChecklists();
        await importTimeTracking();
        await importPomodoro();
        await dbRun('COMMIT');
        return res.json({ success: true });
    } catch (e) {
        try { await dbRun('ROLLBACK'); } catch (rollbackErr) {}
        return res.status(500).json({ error: 'Failed to import data' });
    }
});

app.post('/api/v2/tasks/completed/cleanup', authenticate, async (req, res) => {
    const username = req.user.username;
    const retentionDaysRaw = parseIntSafe(req.body?.retentionDays);
    const retentionDays = Number.isFinite(retentionDaysRaw) ? retentionDaysRaw : 30;
    if (retentionDays === -1) return res.json({ success: true, purged: 0 });
    const days = Math.max(0, retentionDays);
    const threshold = Date.now() - (DAY_MS * days);
    try {
        const result = await dbRun(
            "DELETE FROM tasks_v2 WHERE username = ? AND status = ? AND updated_at < ?",
            [username, 'completed', threshold]
        );
        return res.json({ success: true, purged: result.changes || 0 });
    } catch (e) {
        return res.status(500).json({ error: 'Failed to cleanup completed tasks' });
    }
});

app.post('/api/user/delete', authenticate, async (req, res) => {
    const username = req.user.username;
    const confirm = String(req.body?.confirm || '').trim();
    if (confirm !== 'DELETE') return res.status(400).json({ error: 'Invalid confirmation' });
    try {
        await dbRun('BEGIN TRANSACTION');
        await dbRun("DELETE FROM tasks_v2 WHERE username = ?", [username]);
        await dbRun("DELETE FROM time_entries WHERE username = ?", [username]);
        await dbRun("DELETE FROM time_activities WHERE username = ?", [username]);
        await dbRun("DELETE FROM pomodoro_sessions WHERE username = ?", [username]);
        await dbRun("DELETE FROM pomodoro_daily_stats WHERE username = ?", [username]);
        await dbRun("DELETE FROM pomodoro_state WHERE username = ?", [username]);
        await dbRun("DELETE FROM pomodoro_settings WHERE username = ?", [username]);
        await dbRun("DELETE FROM user_settings WHERE username = ?", [username]);
        await dbRun("DELETE FROM push_subscriptions WHERE username = ?", [username]);
        await dbRun("DELETE FROM fcm_tokens WHERE username = ?", [username]);
        await dbRun("DELETE FROM data WHERE username = ?", [username]);

        const listRows = await dbAll("SELECT id FROM checklists WHERE owner = ?", [username]);
        const listIds = listRows.map((r) => Number(r.id)).filter((id) => Number.isFinite(id) && id > 0);
        for (const listId of listIds) {
            await dbRun("DELETE FROM checklist_shares WHERE list_id = ?", [listId]);
            await dbRun("DELETE FROM checklist_columns WHERE list_id = ?", [listId]);
            await dbRun("DELETE FROM checklist_items WHERE list_id = ?", [listId]);
        }
        await dbRun("DELETE FROM checklists WHERE owner = ?", [username]);

        await dbRun("DELETE FROM users WHERE username = ?", [username]);
        await dbRun('COMMIT');
        return res.json({ success: true });
    } catch (e) {
        try { await dbRun('ROLLBACK'); } catch (rollbackErr) {}
        return res.status(500).json({ error: 'Failed to delete account' });
    }
});

// Pomodoro settings/state/sessions
app.get('/api/pomodoro/settings', authenticate, async (req, res) => {
    try {
        const rows = await dbAll(
            "SELECT work_min, short_break_min, long_break_min, long_break_every, auto_start_next, auto_start_break, auto_start_work, auto_finish_task FROM pomodoro_settings WHERE username = ?",
            [req.user.username]
        );
        if (!rows.length) {
            return res.json({ settings: getPomodoroDefaults() });
        }
        const r = rows[0];
        res.json({
            settings: {
                workMin: r.work_min,
                shortBreakMin: r.short_break_min,
                longBreakMin: r.long_break_min,
                longBreakEvery: r.long_break_every,
                autoStartNext: !!r.auto_start_next,
                autoStartBreak: r.auto_start_break === null || typeof r.auto_start_break === 'undefined' ? !!r.auto_start_next : !!r.auto_start_break,
                autoStartWork: r.auto_start_work === null || typeof r.auto_start_work === 'undefined' ? !!r.auto_start_next : !!r.auto_start_work,
                autoFinishTask: !!r.auto_finish_task
            }
        });
    } catch (e) {
        res.status(500).json({ error: "Failed to load pomodoro settings" });
    }
});

app.post('/api/pomodoro/settings', authenticate, async (req, res) => {
    const defaults = getPomodoroDefaults();
    const workMin = Math.max(1, parseInt(req.body.workMin, 10) || defaults.workMin);
    const shortMin = Math.max(1, parseInt(req.body.shortBreakMin, 10) || defaults.shortBreakMin);
    const longMin = Math.max(1, parseInt(req.body.longBreakMin, 10) || defaults.longBreakMin);
    const longEvery = Math.max(1, parseInt(req.body.longBreakEvery, 10) || defaults.longBreakEvery);
    const autoStartNext = req.body.autoStartNext ? 1 : 0;
    const autoStartBreak = (typeof req.body.autoStartBreak === 'boolean' ? req.body.autoStartBreak : req.body.autoStartNext) ? 1 : 0;
    const autoStartWork = (typeof req.body.autoStartWork === 'boolean' ? req.body.autoStartWork : req.body.autoStartNext) ? 1 : 0;
    const autoFinishTask = req.body.autoFinishTask ? 1 : 0;
    const updatedAt = Date.now();
    try {
        await dbRun(
            `INSERT OR REPLACE INTO pomodoro_settings 
            (username, work_min, short_break_min, long_break_min, long_break_every, auto_start_next, auto_start_break, auto_start_work, auto_finish_task, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [req.user.username, workMin, shortMin, longMin, longEvery, autoStartNext, autoStartBreak, autoStartWork, autoFinishTask, updatedAt]
        );
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: "Failed to save pomodoro settings" });
    }
});

app.get('/api/pomodoro/state', authenticate, async (req, res) => {
    try {
        const rows = await dbAll(
            "SELECT mode, remaining_ms, is_running, target_end, cycle_count, current_task_id FROM pomodoro_state WHERE username = ?",
            [req.user.username]
        );
        if (!rows.length) {
            return res.json({ state: null });
        }
        const r = rows[0];
        res.json({
            state: {
                mode: r.mode,
                remainingMs: r.remaining_ms,
                isRunning: !!r.is_running,
                targetEnd: r.target_end,
                cycleCount: r.cycle_count,
                currentTaskId: r.current_task_id
            }
        });
    } catch (e) {
        res.status(500).json({ error: "Failed to load pomodoro state" });
    }
});

app.post('/api/pomodoro/state', authenticate, async (req, res) => {
    const allowedModes = new Set(['work', 'short', 'long']);
    const mode = allowedModes.has(req.body.mode) ? req.body.mode : 'work';
    const remainingMs = Math.max(0, parseInt(req.body.remainingMs, 10) || 0);
    const isRunning = req.body.isRunning ? 1 : 0;
    const targetEndParsed = parseInt(req.body.targetEnd, 10);
    const targetEnd = Number.isFinite(targetEndParsed) ? targetEndParsed : null;
    const cycleCount = Math.max(0, parseInt(req.body.cycleCount, 10) || 0);
    const currentTaskParsed = parseInt(req.body.currentTaskId, 10);
    const currentTaskId = Number.isFinite(currentTaskParsed) ? currentTaskParsed : null;
    const updatedAt = Date.now();
    try {
        await dbRun(
            `INSERT OR REPLACE INTO pomodoro_state 
            (username, mode, remaining_ms, is_running, target_end, cycle_count, current_task_id, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
            [req.user.username, mode, remainingMs, isRunning, targetEnd, cycleCount, currentTaskId, updatedAt]
        );
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: "Failed to save pomodoro state" });
    }
});

app.get('/api/pomodoro/summary', authenticate, async (req, res) => {
    const days = Math.min(60, Math.max(1, parseInt(req.query.days, 10) || 7));
    try {
        const rows = await dbAll(
            `SELECT date_key, work_sessions, work_minutes, break_minutes 
             FROM pomodoro_daily_stats WHERE username = ? ORDER BY date_key DESC LIMIT ?`,
            [req.user.username, days]
        );
        const totals = await dbAll(
            `SELECT 
                COALESCE(SUM(work_sessions), 0) AS total_sessions,
                COALESCE(SUM(work_minutes), 0) AS total_minutes,
                COALESCE(SUM(break_minutes), 0) AS total_break
             FROM pomodoro_daily_stats WHERE username = ?`,
            [req.user.username]
        );
        const daysMap = {};
        rows.forEach((row) => {
            daysMap[row.date_key] = {
                workSessions: row.work_sessions,
                workMinutes: row.work_minutes,
                breakMinutes: row.break_minutes
            };
        });
        const totalRow = totals[0] || {};
        res.json({
            totals: {
                totalWorkSessions: totalRow.total_sessions || 0,
                totalWorkMinutes: totalRow.total_minutes || 0,
                totalBreakMinutes: totalRow.total_break || 0
            },
            days: daysMap
        });
    } catch (e) {
        res.status(500).json({ error: "Failed to load pomodoro summary" });
    }
});

app.get('/api/pomodoro/sessions', authenticate, async (req, res) => {
    const limit = Math.min(200, Math.max(1, parseInt(req.query.limit, 10) || 50));
    try {
        const rows = await dbAll(
            `SELECT id, task_id, task_title, started_at, ended_at, duration_min 
             FROM pomodoro_sessions WHERE username = ? ORDER BY ended_at DESC LIMIT ?`,
            [req.user.username, limit]
        );
        res.json({ sessions: rows });
    } catch (e) {
        res.status(500).json({ error: "Failed to load pomodoro sessions" });
    }
});

app.post('/api/pomodoro/sessions', authenticate, async (req, res) => {
    const taskIdParsed = parseInt(req.body.taskId, 10);
    const taskId = Number.isFinite(taskIdParsed) ? taskIdParsed : null;
    const taskTitle = req.body.taskTitle ? String(req.body.taskTitle) : null;
    const startedAtParsed = parseInt(req.body.startedAt, 10);
    const startedAt = Number.isFinite(startedAtParsed) ? startedAtParsed : null;
    const endedAtParsed = parseInt(req.body.endedAt, 10);
    const endedAt = Number.isFinite(endedAtParsed) ? endedAtParsed : Date.now();
    const durationMin = Math.max(1, parseInt(req.body.durationMin, 10) || 1);
    const dateKey = req.body.dateKey ? String(req.body.dateKey) : null;
    try {
        await dbRun(
            `INSERT INTO pomodoro_sessions 
            (username, task_id, task_title, started_at, ended_at, duration_min, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)`,
            [req.user.username, taskId, taskTitle, startedAt, endedAt, durationMin, Date.now()]
        );
        if (dateKey) {
            await upsertPomodoroDailyStats(req.user.username, dateKey, durationMin, 0);
        }
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: "Failed to save pomodoro session" });
    }
});

// Push notification APIs
app.get('/api/push/public-key', authenticate, (req, res) => {
    if (!isPushConfigured()) return res.status(500).json({ error: "Push not configured" });
    res.json({ key: VAPID_PUBLIC_KEY });
});

app.post('/api/push/subscribe', authenticate, (req, res) => {
    if (!isPushConfigured()) return res.status(500).json({ error: "Push not configured" });
    const sub = req.body && req.body.subscription;
    if (!sub || !sub.endpoint || !sub.keys || !sub.keys.p256dh || !sub.keys.auth) {
        return res.status(400).json({ error: "Invalid subscription" });
    }
    const now = Date.now();
    db.run(
        "INSERT OR REPLACE INTO push_subscriptions (endpoint, username, p256dh, auth, expiration_time, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        [sub.endpoint, req.user.username, sub.keys.p256dh, sub.keys.auth, sub.expirationTime || null, now],
        () => res.json({ success: true })
    );
});

app.post('/api/push/unsubscribe', authenticate, (req, res) => {
    const endpoint = req.body && req.body.endpoint;
    if (!endpoint) {
        db.run("DELETE FROM push_subscriptions WHERE username = ?", [req.user.username], () => res.json({ success: true }));
        return;
    }
    db.run(
        "DELETE FROM push_subscriptions WHERE endpoint = ? AND username = ?",
        [endpoint, req.user.username],
        () => res.json({ success: true })
    );
});

app.post('/api/push/test', authenticate, async (req, res) => {
    if (!isPushConfigured()) return res.status(500).json({ error: "Push not configured" });
    try {
        const sent = await sendPushToUser(req.user.username, {
            title: '测试通知',
            body: '这是一条测试通知',
            url: '/',
            tag: `test-${Date.now()}`
        });
        if (!sent) return res.status(404).json({ error: "No subscription" });
        res.json({ success: true });
    } catch (e) {
        console.warn('push test failed', e);
        res.status(500).json({ error: "Push test failed" });
    }
});

// Firebase Cloud Messaging (FCM) APIs
app.get('/api/fcm/status', authenticate, async (req, res) => {
    const configured = await ensureFirebaseAdmin();
    res.json({ configured });
});

app.post('/api/fcm/register', authenticate, async (req, res) => {
    const username = req.user.username;
    const token = String(req.body?.token || '').trim();
    const platform = String(req.body?.platform || '').trim();
    if (!token) return res.status(400).json({ error: "Missing token" });

    const now = Date.now();
    try {
        await dbRun(
            "INSERT OR REPLACE INTO fcm_tokens (token, username, platform, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
            [token, username, platform || null, now, now]
        );
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: "Failed to save token" });
    }
});

app.post('/api/fcm/unregister', authenticate, async (req, res) => {
    const username = req.user.username;
    const token = String(req.body?.token || '').trim();
    try {
        if (token) {
            await dbRun("DELETE FROM fcm_tokens WHERE token = ? AND username = ?", [token, username]);
        } else {
            await dbRun("DELETE FROM fcm_tokens WHERE username = ?", [username]);
        }
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ error: "Failed to delete token" });
    }
});

app.post('/api/fcm/test', authenticate, async (req, res) => {
    const configured = await ensureFirebaseAdmin();
    if (!configured) return res.status(500).json({ error: "FCM not configured" });

    try {
        const sent = await sendFcmToUser(req.user.username, {
            title: '测试通知',
            body: '这是一条测试通知',
            url: '/',
            tag: `test-${Date.now()}`
        });
        if (!sent) return res.status(404).json({ error: "No token" });
        res.json({ success: true });
    } catch (e) {
        console.warn('fcm test failed', e);
        res.status(500).json({ error: "FCM test failed" });
    }
});

// 3. 管理员接口
app.get('/api/admin/invite', authenticate, requireAdmin, (req, res) => {
    getOrInitInviteCode((code) => res.json({ code }));
});

app.post('/api/admin/invite/refresh', authenticate, requireAdmin, (req, res) => {
    const newCode = generateInviteCode();
    db.run("UPDATE settings SET value = ? WHERE key = 'invite_code'", [newCode], () => res.json({ code: newCode }));
});

app.get('/api/admin/users', authenticate, requireAdmin, (req, res) => {
    db.all("SELECT username, is_admin FROM users", (err, rows) => res.json({ users: rows }));
});

app.post('/api/admin/reset-pwd', authenticate, requireAdmin, (req, res) => {
    const { targetUser } = req.body;
    db.run("UPDATE users SET password = '123456' WHERE username = ?", [targetUser], function(err) {
        if (this.changes === 0) return res.status(404).json({ error: "User not found" });
        res.json({ success: true, message: "密码已重置为 123456" });
    });
});

app.post('/api/admin/delete-user', authenticate, requireAdmin, (req, res) => {
    const { targetUser } = req.body;
    if (targetUser === req.user.username) return res.status(400).json({ error: "不能删除自己" });
    db.serialize(() => {
        db.run("DELETE FROM users WHERE username = ?", [targetUser]);
        db.run("DELETE FROM data WHERE username = ?", [targetUser]);
    });
    res.json({ success: true });
});

// 4. 修改密码
app.post('/api/change-pwd', authenticate, (req, res) => {
    const { oldPassword, newPassword } = req.body || {};
    if (!oldPassword || !newPassword) return res.status(400).json({ error: "提交参数错误" });
    db.get("SELECT password FROM users WHERE username = ?", [req.user.username], (err, row) => {
        if (err || !row) return res.status(500).json({ error: "DB Error" });
        if (row.password !== oldPassword) return res.status(400).json({ error: "原密码不正确" });
        db.run("UPDATE users SET password = ? WHERE username = ?", [newPassword, req.user.username], function(updateErr) {
            if (updateErr) return res.status(500).json({ error: "DB Error" });
            res.json({ success: true });
        });
    });
});

// 5. 节假日缓存
app.get('/api/holidays/:year', authenticate, async (req, res) => {
    const year = String(req.params.year || '').trim();
    if (!/^\d{4}$/.test(year)) return res.status(400).json({ error: 'Invalid year' });
    const filePath = path.join(holidaysDir, `${year}.json`);
    if (fs.existsSync(filePath)) {
        return res.sendFile(filePath);
    }

    const envBases = String(process.env.HOLIDAY_JSON_URL || '').trim();
    const bases = envBases
        ? envBases.split(',').map((item) => item.trim()).filter(Boolean)
        : [
            'https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/{year}.json',
            'https://fastly.jsdelivr.net/gh/NateScarlet/holiday-cn@master/{year}.json',
            'https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/{year}.json'
        ];

    for (const base of bases) {
        const url = base.includes('{year}') ? base.replace('{year}', year) : base;
        try {
            let data = await fetchText(url);
            data = String(data || '').replace(/^\uFEFF/, '');

            let parsed = JSON.parse(data);
            if (!parsed || typeof parsed !== 'object') throw new Error('Invalid holiday data');
            if (Array.isArray(parsed)) {
                parsed = { year: Number(year), days: parsed };
            } else if (parsed && typeof parsed === 'object') {
                if (typeof parsed.year !== 'number') parsed.year = Number(year);
                if (!Array.isArray(parsed.days)) {
                    if (Array.isArray(parsed.data)) parsed.days = parsed.data;
                    else parsed.days = [];
                }
            }
            data = JSON.stringify(parsed, null, 4);

            try {
                fs.writeFileSync(filePath, data, 'utf8');
            } catch (_) {
                // Ignore caching failures (still return the fetched data).
            }

            return res.type('json').send(data);
        } catch (e) {
            // Try next source.
        }
    }

    return res.status(404).json({ error: 'Holiday data not found' });
});

// --- API v2 routes ---
const DAY_MS = 24 * 60 * 60 * 1000;

const mapTaskRow = (row = {}) => ({
    id: row.id,
    title: row.title || '',
    notes: row.notes || '',
    status: row.status || 'todo',
    dueDate: row.due_date || '',
    startTime: row.start_time || '',
    endDate: row.end_date || '',
    endTime: row.end_time || '',
    tags: parseJsonArray(row.tags_json),
    inbox: !!row.inbox,
    priority: Number(row.priority || 0),
    remindAt: row.remind_at,
    repeatRule: row.repeat_rule || '',
    attachments: normalizeTaskAttachments(row.attachments_json),
    subtasks: normalizeTaskSubtasks(row.subtasks_json),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
    owner: row.username
});

const mapActivityRow = (row = {}) => ({
    id: row.id,
    name: row.name || '',
    taskId: row.task_id || null,
    icon: row.icon || '',
    color: row.color || '',
    category: row.category || '',
    goal: row.goal || '',
    note: row.note || '',
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at
});

const mapEntryRow = (row = {}) => ({
    id: row.id,
    activityId: row.activity_id,
    taskId: row.task_id || null,
    startedAt: row.started_at,
    endedAt: row.ended_at,
    durationMs: row.duration_ms,
    note: row.note || '',
    tags: parseJsonArray(row.tags_json),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at
});

const getRangeFromQuery = (req, now) => {
    const fromRaw = parseIntSafe(req.query.from);
    const toRaw = parseIntSafe(req.query.to);
    const from = Number.isFinite(fromRaw) ? fromRaw : utcDayStartMs(now - (DAY_MS * 6));
    const to = Number.isFinite(toRaw) ? toRaw : now;
    return { from, to };
};

// v2 tasks
app.get('/api/v2/tasks', authenticate, async (req, res) => {
    const view = String(req.query.view || 'all').toLowerCase();
    const includeDeleted = String(req.query.include_deleted || '').toLowerCase() === 'true';
    const updatedSince = parseIntSafe(req.query.updated_since);
    const limit = clampLimit(req.query.limit, 1, 500, 200);
    const offset = Math.max(0, parseInt(req.query.offset, 10) || 0);
    const params = [req.user.username];
    let where = 'username = ?';

    if (!includeDeleted) where += ' AND deleted_at IS NULL';
    if (Number.isFinite(updatedSince)) {
        where += ' AND updated_at > ?';
        params.push(updatedSince);
    }

    const now = Date.now();
    if (view === 'inbox') {
        where += ' AND inbox = 1 AND status != ?';
        params.push('completed');
    } else if (view === 'done') {
        where += ' AND status = ?';
        params.push('completed');
    } else if (view === 'today') {
        where += ' AND due_date = ? AND status != ?';
        params.push(toUtcDateKey(now), 'completed');
    } else if (view === 'tomorrow') {
        where += ' AND due_date = ? AND status != ?';
        params.push(toUtcDateKey(now + DAY_MS), 'completed');
    } else if (view === 'next7') {
        where += ' AND due_date >= ? AND due_date <= ? AND status != ?';
        params.push(toUtcDateKey(now), toUtcDateKey(now + (DAY_MS * 7)), 'completed');
    }

    try {
        const rows = await dbAll(
            `SELECT * FROM tasks_v2 WHERE ${where} ORDER BY updated_at DESC LIMIT ? OFFSET ?`,
            [...params, limit, offset]
        );
        res.json({ tasks: rows.map(mapTaskRow) });
    } catch (e) {
        res.status(500).json({ error: 'Failed to load tasks' });
    }
});

app.get('/api/v2/tasks/:id', authenticate, async (req, res) => {
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'Invalid task id' });
    try {
        const rows = await dbAll(
            "SELECT * FROM tasks_v2 WHERE id = ? AND username = ?",
            [id, req.user.username]
        );
        if (!rows.length) return res.status(404).json({ error: 'Task not found' });
        res.json({ task: mapTaskRow(rows[0]) });
    } catch (e) {
        res.status(500).json({ error: 'Failed to load task' });
    }
});

app.post('/api/v2/tasks', authenticate, async (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const title = String(body.title || '').trim();
    if (!title) return res.status(400).json({ error: 'Title is required' });

    const id = String(body.id || '').trim() || createUuid();
    const now = Date.now();
    const notes = String(body.notes || '').trim();
    const status = normalizeStatus(body.status);
    const dueDate = normalizeDateKey(body.dueDate ?? body.due_date);
    const startTime = String(body.startTime ?? body.start_time ?? '').trim();
    let endDate = normalizeDateKey(body.endDate ?? body.end_date);
    let endTime = String(body.endTime ?? body.end_time ?? '').trim();
    const tags = normalizeTags(body.tags);
    const subtasks = normalizeTaskSubtasks(body.subtasks);
    const inbox = parseBool(body.inbox) ? 1 : 0;
    const priority = Math.max(0, parseIntSafe(body.priority) ?? 0);
    const remindAt = parseIntSafe(body.remindAt ?? body.remind_at);
    const repeatRule = String(body.repeatRule ?? body.repeat_rule ?? '').trim();

    // Legacy compatibility: accept endTime encoded as "HH:mm+N" or "24:00" and derive endDate.
    // Normalized storage: end_time should be "HH:mm" and end_date is the absolute date key.
    if (endTime.includes('+')) {
        const plusIndex = endTime.lastIndexOf('+');
        const rawOffset = parseIntSafe(endTime.substring(plusIndex + 1).trim()) ?? 0;
        const offsetDays = Math.max(0, rawOffset);
        const timePart = endTime.substring(0, plusIndex).trim();
        endTime = timePart;
        if (timePart === '24:00') {
            endTime = '00:00';
            endDate = dueDate ? toUtcDateKey(utcDayStartMs(Date.parse(`${dueDate}T00:00:00Z`) + DAY_MS * (offsetDays + 1))) : endDate;
        } else if (dueDate && offsetDays > 0) {
            endDate = toUtcDateKey(utcDayStartMs(Date.parse(`${dueDate}T00:00:00Z`) + DAY_MS * offsetDays));
        }
    } else if (endTime === '24:00') {
        endTime = '00:00';
        if (dueDate) {
            endDate = toUtcDateKey(utcDayStartMs(Date.parse(`${dueDate}T00:00:00Z`) + DAY_MS));
        }
    }
    if (!endDate && dueDate && endTime) {
        endDate = dueDate;
        if (startTime && endTime <= startTime) {
            endDate = toUtcDateKey(utcDayStartMs(Date.parse(`${dueDate}T00:00:00Z`) + DAY_MS));
        }
    }
    if (dueDate && endDate && endDate < dueDate) {
        endDate = dueDate;
    }

    try {
        await dbRun(
            `INSERT INTO tasks_v2
            (id, username, title, notes, status, due_date, start_time, end_date, end_time, tags_json, subtasks_json, attachments_json, inbox, priority, remind_at, repeat_rule, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                id,
                req.user.username,
                title,
                notes,
                status,
                dueDate || null,
                startTime || null,
                endDate || null,
                endTime || null,
                JSON.stringify(tags),
                JSON.stringify(subtasks),
                JSON.stringify([]),
                inbox,
                priority,
                remindAt,
                repeatRule || null,
                now,
                now,
                null
            ]
        );
        res.json({
            task: mapTaskRow({
                id,
                username: req.user.username,
                title,
                notes,
                status,
                due_date: dueDate || null,
                start_time: startTime || null,
                end_date: endDate || null,
                end_time: endTime || null,
                tags_json: JSON.stringify(tags),
                subtasks_json: JSON.stringify(subtasks),
                attachments_json: JSON.stringify([]),
                inbox,
                priority,
                remind_at: remindAt,
                repeat_rule: repeatRule || null,
                created_at: now,
                updated_at: now,
                deleted_at: null
            })
        });
    } catch (e) {
        const message = String(e?.message || '');
        if (message.includes('UNIQUE') || message.includes('PRIMARY KEY')) {
            return res.status(409).json({ error: 'Task id already exists' });
        }
        res.status(500).json({ error: 'Failed to create task' });
    }
});

app.patch('/api/v2/tasks/:id', authenticate, async (req, res) => {
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'Invalid task id' });
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const fields = [];
    const values = [];

    if (body.title !== undefined) {
        const title = String(body.title || '').trim();
        if (!title) return res.status(400).json({ error: 'Title is required' });
        fields.push('title = ?');
        values.push(title);
    }
    if (body.notes !== undefined) {
        fields.push('notes = ?');
        values.push(String(body.notes || '').trim());
    }
    if (body.status !== undefined) {
        fields.push('status = ?');
        values.push(normalizeStatus(body.status));
    }
    if (body.dueDate !== undefined || body.due_date !== undefined) {
        const dueDate = normalizeDateKey(body.dueDate ?? body.due_date);
        fields.push('due_date = ?');
        values.push(dueDate || null);
    }
    if (body.startTime !== undefined || body.start_time !== undefined) {
        const startTime = String(body.startTime ?? body.start_time ?? '').trim();
        fields.push('start_time = ?');
        values.push(startTime || null);
    }
    if (body.endDate !== undefined || body.end_date !== undefined) {
        const endDate = normalizeDateKey(body.endDate ?? body.end_date);
        fields.push('end_date = ?');
        values.push(endDate || null);
    }
    if (body.endTime !== undefined || body.end_time !== undefined) {
        const endTime = String(body.endTime ?? body.end_time ?? '').trim();
        fields.push('end_time = ?');
        values.push(endTime || null);
    }
    if (body.tags !== undefined) {
        fields.push('tags_json = ?');
        values.push(JSON.stringify(normalizeTags(body.tags)));
    }
    if (body.subtasks !== undefined) {
        fields.push('subtasks_json = ?');
        values.push(JSON.stringify(normalizeTaskSubtasks(body.subtasks)));
    }
    if (body.inbox !== undefined) {
        fields.push('inbox = ?');
        values.push(parseBool(body.inbox) ? 1 : 0);
    }
    if (body.priority !== undefined) {
        fields.push('priority = ?');
        values.push(Math.max(0, parseIntSafe(body.priority) ?? 0));
    }
    if (body.remindAt !== undefined || body.remind_at !== undefined) {
        fields.push('remind_at = ?');
        values.push(parseIntSafe(body.remindAt ?? body.remind_at));
    }
    if (body.repeatRule !== undefined || body.repeat_rule !== undefined) {
        const repeatRule = String(body.repeatRule ?? body.repeat_rule ?? '').trim();
        fields.push('repeat_rule = ?');
        values.push(repeatRule || null);
    }
    if (body.deletedAt !== undefined || body.deleted_at !== undefined) {
        fields.push('deleted_at = ?');
        values.push(parseIntSafe(body.deletedAt ?? body.deleted_at));
    }

    if (!fields.length) return res.status(400).json({ error: 'No fields to update' });
    fields.push('updated_at = ?');
    values.push(Date.now());

    try {
        const result = await dbRun(
            `UPDATE tasks_v2 SET ${fields.join(', ')} WHERE id = ? AND username = ?`,
            [...values, id, req.user.username]
        );
        if (!result || result.changes === 0) return res.status(404).json({ error: 'Task not found' });
        const rows = await dbAll(
            "SELECT * FROM tasks_v2 WHERE id = ? AND username = ?",
            [id, req.user.username]
        );
        res.json({ task: rows.length ? mapTaskRow(rows[0]) : null });
    } catch (e) {
        res.status(500).json({ error: 'Failed to update task' });
    }
});

app.delete('/api/v2/tasks/:id', authenticate, async (req, res) => {
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'Invalid task id' });
    const now = Date.now();
    try {
        const result = await dbRun(
            "UPDATE tasks_v2 SET deleted_at = ?, updated_at = ? WHERE id = ? AND username = ?",
            [now, now, id, req.user.username]
        );
        if (!result || result.changes === 0) return res.status(404).json({ error: 'Task not found' });
        res.json({ success: true, deletedAt: now });
    } catch (e) {
        res.status(500).json({ error: 'Failed to delete task' });
    }
});

app.delete('/api/v2/tasks/trash/empty', authenticate, async (req, res) => {
    try {
        const rows = await dbAll(
            "SELECT id FROM tasks_v2 WHERE username = ? AND deleted_at IS NOT NULL",
            [req.user.username]
        );
        if (!rows.length) return res.json({ success: true, purged: 0 });
        const ids = rows.map(r => String(r.id));
        const placeholders = ids.map(() => '?').join(',');

        let attachmentRows = [];
        try {
            attachmentRows = await dbAll(
                `SELECT id, storage_driver, storage_path FROM attachments WHERE owner_user_id = ? AND task_id IN (${placeholders})`,
                [req.user.username, ...ids]
            );
        } catch (e) {
            attachmentRows = [];
        }

        await dbRun('BEGIN');
        if (attachmentRows.length) {
            await dbRun(
                `DELETE FROM attachments WHERE owner_user_id = ? AND task_id IN (${placeholders})`,
                [req.user.username, ...ids]
            );
        }
        await dbRun(
            "DELETE FROM tasks_v2 WHERE username = ? AND deleted_at IS NOT NULL",
            [req.user.username]
        );
        await dbRun('COMMIT');

        for (const attachment of attachmentRows) {
            try {
                await deleteAttachmentFile({
                    storageDriver: attachment.storage_driver,
                    storagePath: attachment.storage_path
                });
            } catch (e) {
                console.warn('delete attachment file failed', e);
            }
        }

        return res.json({ success: true, purged: rows.length });
    } catch (e) {
        try { await dbRun('ROLLBACK'); } catch (rollbackErr) {}
        return res.status(500).json({ error: 'Failed to empty trash' });
    }
});

app.post('/api/v2/tasks/:taskId/attachments', authenticate, (req, res) => {
    attachmentUpload.single('file')(req, res, async (err) => {
        if (err) return res.status(400).json({ error: err.message || 'Upload failed' });
        if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

        const taskId = String(req.params.taskId || '').trim();
        if (!taskId) {
            fs.unlink(req.file.path, () => {});
            return res.status(400).json({ error: 'Invalid task id' });
        }

        let stored = null;
        try {
            const rows = await dbAll(
                "SELECT id, attachments_json FROM tasks_v2 WHERE id = ? AND username = ?",
                [taskId, req.user.username]
            );
            const task = rows[0];
            if (!task) {
                fs.unlink(req.file.path, () => {});
                return res.status(404).json({ error: 'Task not found' });
            }

            const originalName = normalizeOriginalName(req.file.originalname);
            const mimeType = req.file.mimetype || 'application/octet-stream';
            const size = req.file.size || 0;
            const attachmentId = req.attachmentId;
            const attachmentExt = req.attachmentExt || '';

            stored = await storeAttachmentFile({
                tmpPath: req.file.path,
                id: attachmentId,
                ext: attachmentExt,
                mimeType,
                originalName,
                size
            });

            const createdAt = Date.now();
            const attachmentMeta = {
                id: attachmentId,
                name: originalName,
                mime: mimeType,
                size,
                createdAt
            };

            const attachments = normalizeTaskAttachments(task.attachments_json);
            attachments.push(attachmentMeta);

            await dbRun('BEGIN');
            await dbRun(
                `INSERT INTO attachments
                (id, owner_user_id, task_id, original_name, mime_type, size, storage_driver, storage_path, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [
                    attachmentId,
                    req.user.username,
                    taskId,
                    originalName,
                    mimeType,
                    size,
                    stored.storageDriver,
                    stored.storagePath,
                    createdAt
                ]
            );
            await dbRun(
                "UPDATE tasks_v2 SET attachments_json = ?, updated_at = ? WHERE id = ? AND username = ?",
                [JSON.stringify(attachments), createdAt, taskId, req.user.username]
            );
            await dbRun('COMMIT');

            return res.json({ success: true, attachment: attachmentMeta });
        } catch (e) {
            try { await dbRun('ROLLBACK'); } catch (rollbackErr) {}
            if (req.file?.path) fs.unlink(req.file.path, () => {});
            if (stored) {
                try {
                    await deleteAttachmentFile({
                        storageDriver: stored.storageDriver,
                        storagePath: stored.storagePath
                    });
                } catch (cleanupErr) {}
            }
            return res.status(500).json({ error: 'Attachment upload failed' });
        }
    });
});

// v2 time activities
app.get('/api/v2/time/activities', authenticate, async (req, res) => {
    const includeDeleted = String(req.query.include_deleted || '').toLowerCase() === 'true';
    const updatedSince = parseIntSafe(req.query.updated_since);
    const limit = clampLimit(req.query.limit, 1, 500, 200);
    const offset = Math.max(0, parseInt(req.query.offset, 10) || 0);
    const params = [req.user.username];
    let where = 'username = ?';
    if (!includeDeleted) where += ' AND deleted_at IS NULL';
    if (Number.isFinite(updatedSince)) {
        where += ' AND updated_at > ?';
        params.push(updatedSince);
    }
    try {
        const rows = await dbAll(
            `SELECT * FROM time_activities WHERE ${where} ORDER BY updated_at DESC LIMIT ? OFFSET ?`,
            [...params, limit, offset]
        );
        res.json({ activities: rows.map(mapActivityRow) });
    } catch (e) {
        res.status(500).json({ error: 'Failed to load activities' });
    }
});

app.post('/api/v2/time/activities', authenticate, async (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const name = String(body.name || '').trim();
    if (!name) return res.status(400).json({ error: 'Name is required' });
    const id = String(body.id || '').trim() || createUuid();
    const taskId = String(body.taskId || body.task_id || '').trim();
    const icon = String(body.icon || '').trim();
    const color = String(body.color || '').trim();
    const category = String(body.category || '').trim();
    const goal = String(body.goal || '').trim();
    const note = String(body.note || '').trim();
    const now = Date.now();
    try {
        await dbRun(
            `INSERT INTO time_activities
            (id, username, task_id, name, icon, color, category, goal, note, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                id,
                req.user.username,
                taskId || null,
                name,
                icon || null,
                color || null,
                category || null,
                goal || null,
                note || null,
                now,
                now,
                null
            ]
        );
        res.json({
            activity: mapActivityRow({
                id,
                username: req.user.username,
                task_id: taskId || null,
                name,
                icon: icon || '',
                color: color || '',
                category: category || '',
                goal: goal || '',
                note: note || '',
                created_at: now,
                updated_at: now,
                deleted_at: null
            })
        });
    } catch (e) {
        const message = String(e?.message || '');
        if (message.includes('UNIQUE') || message.includes('PRIMARY KEY')) {
            return res.status(409).json({ error: 'Activity id already exists' });
        }
        res.status(500).json({ error: 'Failed to create activity' });
    }
});

app.patch('/api/v2/time/activities/:id', authenticate, async (req, res) => {
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'Invalid activity id' });
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const fields = [];
    const values = [];

    if (body.name !== undefined) {
        const name = String(body.name || '').trim();
        if (!name) return res.status(400).json({ error: 'Name is required' });
        fields.push('name = ?');
        values.push(name);
    }
    if (body.taskId !== undefined || body.task_id !== undefined) {
        const taskId = String(body.taskId || body.task_id || '').trim();
        fields.push('task_id = ?');
        values.push(taskId || null);
    }
    if (body.icon !== undefined) {
        const icon = String(body.icon || '').trim();
        fields.push('icon = ?');
        values.push(icon || null);
    }
    if (body.color !== undefined) {
        const color = String(body.color || '').trim();
        fields.push('color = ?');
        values.push(color || null);
    }
    if (body.category !== undefined) {
        const category = String(body.category || '').trim();
        fields.push('category = ?');
        values.push(category || null);
    }
    if (body.goal !== undefined) {
        const goal = String(body.goal || '').trim();
        fields.push('goal = ?');
        values.push(goal || null);
    }
    if (body.note !== undefined) {
        const note = String(body.note || '').trim();
        fields.push('note = ?');
        values.push(note || null);
    }
    if (body.deletedAt !== undefined || body.deleted_at !== undefined) {
        fields.push('deleted_at = ?');
        values.push(parseIntSafe(body.deletedAt ?? body.deleted_at));
    }

    if (!fields.length) return res.status(400).json({ error: 'No fields to update' });
    fields.push('updated_at = ?');
    values.push(Date.now());

    try {
        const result = await dbRun(
            `UPDATE time_activities SET ${fields.join(', ')} WHERE id = ? AND username = ?`,
            [...values, id, req.user.username]
        );
        if (!result || result.changes === 0) return res.status(404).json({ error: 'Activity not found' });
        const rows = await dbAll(
            "SELECT * FROM time_activities WHERE id = ? AND username = ?",
            [id, req.user.username]
        );
        res.json({ activity: rows.length ? mapActivityRow(rows[0]) : null });
    } catch (e) {
        res.status(500).json({ error: 'Failed to update activity' });
    }
});

app.delete('/api/v2/time/activities/:id', authenticate, async (req, res) => {
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'Invalid activity id' });
    const now = Date.now();
    try {
        const result = await dbRun(
            "UPDATE time_activities SET deleted_at = ?, updated_at = ? WHERE id = ? AND username = ?",
            [now, now, id, req.user.username]
        );
        if (!result || result.changes === 0) return res.status(404).json({ error: 'Activity not found' });
        res.json({ success: true, deletedAt: now });
    } catch (e) {
        res.status(500).json({ error: 'Failed to delete activity' });
    }
});

// v2 time entries
app.get('/api/v2/time/entries', authenticate, async (req, res) => {
    const includeDeleted = String(req.query.include_deleted || '').toLowerCase() === 'true';
    const runningOnly = String(req.query.running_only || '').toLowerCase() === 'true';
    const activityId = String(req.query.activity_id || '').trim();
    const taskId = String(req.query.task_id || '').trim();
    const limit = clampLimit(req.query.limit, 1, 500, 200);
    const offset = Math.max(0, parseInt(req.query.offset, 10) || 0);
    const params = [req.user.username];
    let where = 'username = ?';

    if (!includeDeleted) where += ' AND deleted_at IS NULL';
    if (activityId) {
        where += ' AND activity_id = ?';
        params.push(activityId);
    }
    if (taskId) {
        where += ' AND task_id = ?';
        params.push(taskId);
    }
    if (runningOnly) {
        where += ' AND ended_at IS NULL';
    }

    const hasRange = req.query.from !== undefined || req.query.to !== undefined;
    if (hasRange) {
        const now = Date.now();
        const { from, to } = getRangeFromQuery(req, now);
        if (to <= from) return res.status(400).json({ error: 'Invalid range' });
        where += ' AND started_at < ? AND (ended_at IS NULL OR ended_at > ?)';
        params.push(to, from);
    }

    try {
        const rows = await dbAll(
            `SELECT * FROM time_entries WHERE ${where} ORDER BY started_at DESC LIMIT ? OFFSET ?`,
            [...params, limit, offset]
        );
        res.json({ entries: rows.map(mapEntryRow) });
    } catch (e) {
        res.status(500).json({ error: 'Failed to load entries' });
    }
});

app.get('/api/v2/time/entries/running', authenticate, async (req, res) => {
    try {
        const rows = await dbAll(
            "SELECT * FROM time_entries WHERE username = ? AND ended_at IS NULL AND deleted_at IS NULL ORDER BY started_at DESC",
            [req.user.username]
        );
        res.json({ entries: rows.map(mapEntryRow) });
    } catch (e) {
        res.status(500).json({ error: 'Failed to load running entries' });
    }
});

app.post('/api/v2/time/entries/start', authenticate, async (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const activityId = String(body.activityId || body.activity_id || '').trim();
    if (!activityId) return res.status(400).json({ error: 'Activity id is required' });
    const taskId = String(body.taskId || body.task_id || '').trim();
    const startedAt = parseIntSafe(body.startedAt ?? body.started_at) ?? Date.now();
    const note = String(body.note || '').trim();
    const tags = normalizeTags(body.tags);
    const id = String(body.id || '').trim() || createUuid();
    const now = Date.now();

    try {
        const activityRows = await dbAll(
            "SELECT id FROM time_activities WHERE id = ? AND username = ? AND deleted_at IS NULL",
            [activityId, req.user.username]
        );
        if (!activityRows.length) return res.status(404).json({ error: 'Activity not found' });

        await dbRun(
            `INSERT INTO time_entries
            (id, username, activity_id, task_id, started_at, ended_at, duration_ms, note, tags_json, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                id,
                req.user.username,
                activityId,
                taskId || null,
                startedAt,
                null,
                null,
                note || null,
                JSON.stringify(tags),
                now,
                now,
                null
            ]
        );
        res.json({
            entry: mapEntryRow({
                id,
                username: req.user.username,
                activity_id: activityId,
                task_id: taskId || null,
                started_at: startedAt,
                ended_at: null,
                duration_ms: null,
                note: note || '',
                tags_json: JSON.stringify(tags),
                created_at: now,
                updated_at: now,
                deleted_at: null
            })
        });
    } catch (e) {
        const message = String(e?.message || '');
        if (message.includes('UNIQUE') || message.includes('PRIMARY KEY')) {
            return res.status(409).json({ error: 'Entry id already exists' });
        }
        res.status(500).json({ error: 'Failed to start entry' });
    }
});

app.post('/api/v2/time/entries/:id/stop', authenticate, async (req, res) => {
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'Invalid entry id' });
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const endedAt = parseIntSafe(body.endedAt ?? body.ended_at) ?? Date.now();
    const now = Date.now();

    try {
        const rows = await dbAll(
            "SELECT * FROM time_entries WHERE id = ? AND username = ? AND deleted_at IS NULL",
            [id, req.user.username]
        );
        if (!rows.length) return res.status(404).json({ error: 'Entry not found' });
        const entry = rows[0];
        if (entry.ended_at) return res.json({ entry: mapEntryRow(entry) });
        if (endedAt < entry.started_at) return res.status(400).json({ error: 'Invalid end time' });
        const duration = endedAt - entry.started_at;
        await dbRun(
            "UPDATE time_entries SET ended_at = ?, duration_ms = ?, updated_at = ? WHERE id = ? AND username = ?",
            [endedAt, duration, now, id, req.user.username]
        );
        const updated = await dbAll(
            "SELECT * FROM time_entries WHERE id = ? AND username = ?",
            [id, req.user.username]
        );
        res.json({ entry: updated.length ? mapEntryRow(updated[0]) : null });
    } catch (e) {
        res.status(500).json({ error: 'Failed to stop entry' });
    }
});

app.patch('/api/v2/time/entries/:id', authenticate, async (req, res) => {
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'Invalid entry id' });
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const now = Date.now();

    try {
        const rows = await dbAll(
            "SELECT * FROM time_entries WHERE id = ? AND username = ? AND deleted_at IS NULL",
            [id, req.user.username]
        );
        if (!rows.length) return res.status(404).json({ error: 'Entry not found' });
        const current = rows[0];

        let nextActivityId = current.activity_id;
        let nextTaskId = current.task_id || null;
        let nextStartedAt = current.started_at;
        let nextEndedAt = current.ended_at;
        let shouldUpdateDuration = false;

        if (body.activityId !== undefined || body.activity_id !== undefined) {
            const activityId = String(body.activityId || body.activity_id || '').trim();
            if (!activityId) return res.status(400).json({ error: 'Activity id is required' });
            const activityRows = await dbAll(
                "SELECT id, task_id FROM time_activities WHERE id = ? AND username = ? AND deleted_at IS NULL",
                [activityId, req.user.username]
            );
            if (!activityRows.length) return res.status(404).json({ error: 'Activity not found' });
            nextActivityId = activityId;
            if (body.taskId === undefined && body.task_id === undefined) {
                nextTaskId = activityRows[0].task_id || null;
            }
        }

        if (body.taskId !== undefined || body.task_id !== undefined) {
            const taskId = String(body.taskId || body.task_id || '').trim();
            nextTaskId = taskId || null;
        }

        if (body.startedAt !== undefined || body.started_at !== undefined) {
            const startedAt = parseIntSafe(body.startedAt ?? body.started_at);
            if (!Number.isFinite(startedAt)) return res.status(400).json({ error: 'Invalid start time' });
            nextStartedAt = startedAt;
            shouldUpdateDuration = true;
        }

        if (body.endedAt !== undefined || body.ended_at !== undefined) {
            const endedRaw = body.endedAt ?? body.ended_at;
            if (endedRaw === null) {
                nextEndedAt = null;
                shouldUpdateDuration = true;
            } else {
                const endedAt = parseIntSafe(endedRaw);
                if (!Number.isFinite(endedAt)) return res.status(400).json({ error: 'Invalid end time' });
                nextEndedAt = endedAt;
                shouldUpdateDuration = true;
            }
        }

        if (nextEndedAt !== null && nextEndedAt < nextStartedAt) {
            return res.status(400).json({ error: 'Invalid time range' });
        }

        const fields = [];
        const values = [];

        if (nextActivityId !== current.activity_id) {
            fields.push('activity_id = ?');
            values.push(nextActivityId);
        }
        if (nextTaskId !== (current.task_id || null)) {
            fields.push('task_id = ?');
            values.push(nextTaskId);
        }
        if (nextStartedAt !== current.started_at) {
            fields.push('started_at = ?');
            values.push(nextStartedAt);
        }
        if (nextEndedAt !== current.ended_at) {
            fields.push('ended_at = ?');
            values.push(nextEndedAt);
        }
        if (shouldUpdateDuration) {
            const duration = nextEndedAt === null ? null : (nextEndedAt - nextStartedAt);
            fields.push('duration_ms = ?');
            values.push(duration);
        }

        if (body.note !== undefined) {
            const note = String(body.note || '').trim();
            fields.push('note = ?');
            values.push(note || null);
        }

        if (body.tags !== undefined) {
            fields.push('tags_json = ?');
            values.push(JSON.stringify(normalizeTags(body.tags)));
        }

        if (body.deletedAt !== undefined || body.deleted_at !== undefined) {
            fields.push('deleted_at = ?');
            values.push(parseIntSafe(body.deletedAt ?? body.deleted_at));
        }

        if (!fields.length) return res.status(400).json({ error: 'No fields to update' });
        fields.push('updated_at = ?');
        values.push(now);

        const result = await dbRun(
            `UPDATE time_entries SET ${fields.join(', ')} WHERE id = ? AND username = ?`,
            [...values, id, req.user.username]
        );
        if (!result || result.changes === 0) return res.status(404).json({ error: 'Entry not found' });

        const updated = await dbAll(
            "SELECT * FROM time_entries WHERE id = ? AND username = ?",
            [id, req.user.username]
        );
        res.json({ entry: updated.length ? mapEntryRow(updated[0]) : null });
    } catch (e) {
        res.status(500).json({ error: 'Failed to update entry' });
    }
});

app.delete('/api/v2/time/entries/:id', authenticate, async (req, res) => {
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'Invalid entry id' });
    const now = Date.now();
    try {
        const result = await dbRun(
            "UPDATE time_entries SET deleted_at = ?, updated_at = ? WHERE id = ? AND username = ?",
            [now, now, id, req.user.username]
        );
        if (!result || result.changes === 0) return res.status(404).json({ error: 'Entry not found' });
        res.json({ success: true, deletedAt: now });
    } catch (e) {
        res.status(500).json({ error: 'Failed to delete entry' });
    }
});

// v2 time stats
app.get('/api/v2/time/stats', authenticate, async (req, res) => {
    const now = Date.now();
    const { from, to } = getRangeFromQuery(req, now);
    if (to <= from) return res.status(400).json({ error: 'Invalid range' });

    try {
        const rows = await dbAll(
            `SELECT activity_id, started_at, ended_at
             FROM time_entries
             WHERE username = ? AND deleted_at IS NULL
               AND started_at < ? AND (ended_at IS NULL OR ended_at > ?)`,
            [req.user.username, to, from]
        );

        const byDay = {};
        const byActivity = {};
        let totalMs = 0;

        rows.forEach((row) => {
            const start = Math.max(row.started_at, from);
            const end = Math.min(row.ended_at || now, to);
            if (end <= start) return;
            const duration = end - start;
            totalMs += duration;

            const activityId = row.activity_id;
            byActivity[activityId] = (byActivity[activityId] || 0) + duration;

            let cursor = start;
            while (cursor < end) {
                const dayStart = utcDayStartMs(cursor);
                const dayEnd = dayStart + DAY_MS;
                const segEnd = Math.min(end, dayEnd);
                const key = toUtcDateKey(cursor);
                byDay[key] = (byDay[key] || 0) + (segEnd - cursor);
                cursor = segEnd;
            }
        });

        res.json({
            range: { from, to },
            totals: { totalMs },
            byDay,
            byActivity
        });
    } catch (e) {
        res.status(500).json({ error: 'Failed to load stats' });
    }
});

// 6. CLI 重置命令
if (process.argv[2] === '--reset-admin') {
    const user = process.argv[3];
    const pass = process.argv[4];
    if (user && pass) {
        const dbCli = new (require('sqlite3').verbose()).Database(path.join(__dirname, 'database.sqlite'));
        dbCli.run("UPDATE users SET password = ?, is_admin = 1 WHERE username = ?", [pass, user], function(err) {
            console.log(this.changes > 0 ? `SUCCESS: User [${user}] is now Admin.` : `FAILED: User [${user}] not found.`);
            process.exit();
        });
    } else {
        console.log("Usage: node server.js --reset-admin <username> <newpassword>");
        process.exit();
    }
} else {
    const startServer = async () => {
        try {
            await ensureVapidKeys();
        } catch (e) {
            console.warn('vapid init failed', e);
        }
        app.listen(PORT, '0.0.0.0', () => {
            console.log(`\n=== Glass Todo Modular Server Running ===`);
            console.log(`Local: http://localhost:${PORT}`);
            console.log(`=========================================\n`);
        });
    };
    startServer();
}
