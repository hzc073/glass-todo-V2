const { AsyncLocalStorage } = require('async_hooks');
const { Pool, types } = require('pg');

// Parse BIGINT (int8) as number (epoch ms fits safely in JS number).
types.setTypeParser(20, (value) => (value === null ? null : Number(value)));

const txStorage = new AsyncLocalStorage();

const AUTO_ID_TABLES = new Set([
    'checklists',
    'checklist_items',
    'checklist_columns',
    'checklist_shares',
    'checklist_share_invites',
    'checklist_audit_logs',
    'user_notifications',
    'pomodoro_sessions'
]);

const UPSERT_TARGETS = {
    settings: ['key'],
    data: ['username'],
    user_settings: ['username'],
    tasks_v2: ['id'],
    attachments: ['id'],
    checklists: ['id'],
    checklist_items: ['id'],
    checklist_columns: ['id'],
    checklist_shares: ['list_id', 'shared_user'],
    checklist_item_attachments: ['id'],
    user_public_ids: ['user_key'],
    checklist_share_invites: ['id'],
    checklist_audit_logs: ['id'],
    user_notifications: ['id'],
    time_activities: ['id'],
    time_entries: ['id'],
    time_activity_goals: ['username', 'activity_id'],
    pomodoro_settings: ['username'],
    pomodoro_state: ['username'],
    pomodoro_sessions: ['id'],
    pomodoro_daily_stats: ['username', 'date_key'],
    push_subscriptions: ['endpoint'],
    fcm_tokens: ['token']
};

const shouldUseSsl = (() => {
    const raw = String(process.env.DB_SSL || '').trim().toLowerCase();
    return raw === '1' || raw === 'true' || raw === 'yes';
})();

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: shouldUseSsl ? { rejectUnauthorized: false } : undefined
});

let schemaInitPromise = null;

const ensureSchema = async () => {
    if (schemaInitPromise) return schemaInitPromise;
    schemaInitPromise = (async () => {
        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            await client.query(`CREATE TABLE IF NOT EXISTS users (
                username TEXT PRIMARY KEY,
                password TEXT,
                is_admin INTEGER DEFAULT 0
            )`);

            await client.query(`CREATE TABLE IF NOT EXISTS data (
                username TEXT PRIMARY KEY,
                json_data TEXT,
                version BIGINT
            )`);

            await client.query(`CREATE TABLE IF NOT EXISTS tasks_v2 (
                id TEXT PRIMARY KEY,
                username TEXT NOT NULL,
                title TEXT NOT NULL,
                notes TEXT,
                status TEXT NOT NULL,
                due_date TEXT,
                start_time TEXT,
                end_date TEXT,
                end_time TEXT,
                tags_json TEXT,
                subtasks_json TEXT,
                attachments_json TEXT,
                inbox INTEGER NOT NULL DEFAULT 0,
                priority INTEGER NOT NULL DEFAULT 0,
                remind_at BIGINT,
                notified_at BIGINT,
                repeat_rule TEXT,
                created_at BIGINT NOT NULL,
                updated_at BIGINT NOT NULL,
                deleted_at BIGINT
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_tasks_v2_user_updated ON tasks_v2(username, updated_at)');
            await client.query('CREATE INDEX IF NOT EXISTS idx_tasks_v2_user_due ON tasks_v2(username, due_date)');

            await client.query(`CREATE TABLE IF NOT EXISTS time_activities (
                id TEXT PRIMARY KEY,
                username TEXT NOT NULL,
                task_id TEXT,
                name TEXT NOT NULL,
                icon TEXT,
                color TEXT,
                category TEXT,
                goal TEXT,
                note TEXT,
                created_at BIGINT NOT NULL,
                updated_at BIGINT NOT NULL,
                deleted_at BIGINT
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_time_activities_user ON time_activities(username, updated_at)');
            await client.query('CREATE INDEX IF NOT EXISTS idx_time_activities_task ON time_activities(task_id)');

            await client.query(`CREATE TABLE IF NOT EXISTS time_entries (
                id TEXT PRIMARY KEY,
                username TEXT NOT NULL,
                activity_id TEXT NOT NULL,
                task_id TEXT,
                started_at BIGINT NOT NULL,
                ended_at BIGINT,
                duration_ms BIGINT,
                note TEXT,
                tags_json TEXT,
                created_at BIGINT NOT NULL,
                updated_at BIGINT NOT NULL,
                deleted_at BIGINT
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_time_entries_user_time ON time_entries(username, started_at)');
            await client.query('CREATE INDEX IF NOT EXISTS idx_time_entries_activity ON time_entries(activity_id)');

            await client.query(`CREATE TABLE IF NOT EXISTS time_activity_goals (
                username TEXT NOT NULL,
                activity_id TEXT NOT NULL,
                daily_duration_ms BIGINT,
                daily_count INTEGER,
                weekly_duration_ms BIGINT,
                weekly_count INTEGER,
                total_duration_ms BIGINT,
                total_count INTEGER,
                created_at BIGINT NOT NULL,
                updated_at BIGINT NOT NULL,
                PRIMARY KEY (username, activity_id)
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_time_activity_goals_user_updated ON time_activity_goals(username, updated_at)');
            await client.query('CREATE INDEX IF NOT EXISTS idx_time_activity_goals_activity ON time_activity_goals(activity_id)');

            await client.query(`CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT
            )`);

            await client.query(`CREATE TABLE IF NOT EXISTS user_settings (
                username TEXT PRIMARY KEY,
                settings_json TEXT,
                updated_at BIGINT NOT NULL
            )`);

            await client.query(`CREATE TABLE IF NOT EXISTS push_subscriptions (
                endpoint TEXT PRIMARY KEY,
                username TEXT,
                p256dh TEXT,
                auth TEXT,
                expiration_time BIGINT,
                created_at BIGINT
            )`);

            await client.query(`CREATE TABLE IF NOT EXISTS fcm_tokens (
                token TEXT PRIMARY KEY,
                username TEXT NOT NULL,
                platform TEXT,
                created_at BIGINT NOT NULL,
                updated_at BIGINT NOT NULL
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user ON fcm_tokens(username, updated_at)');

            await client.query(`CREATE TABLE IF NOT EXISTS pomodoro_settings (
                username TEXT PRIMARY KEY,
                work_min INTEGER NOT NULL,
                short_break_min INTEGER NOT NULL,
                long_break_min INTEGER NOT NULL,
                long_break_every INTEGER NOT NULL,
                auto_start_next INTEGER NOT NULL DEFAULT 0,
                auto_start_break INTEGER NOT NULL DEFAULT 0,
                auto_start_work INTEGER NOT NULL DEFAULT 0,
                auto_finish_task INTEGER NOT NULL DEFAULT 0,
                updated_at BIGINT NOT NULL
            )`);

            await client.query(`CREATE TABLE IF NOT EXISTS pomodoro_state (
                username TEXT PRIMARY KEY,
                mode TEXT NOT NULL,
                remaining_ms BIGINT NOT NULL,
                is_running INTEGER NOT NULL,
                target_end BIGINT,
                cycle_count INTEGER NOT NULL DEFAULT 0,
                current_task_id BIGINT,
                updated_at BIGINT NOT NULL
            )`);

            await client.query(`CREATE TABLE IF NOT EXISTS pomodoro_sessions (
                id SERIAL PRIMARY KEY,
                username TEXT NOT NULL,
                task_id BIGINT,
                task_title TEXT,
                started_at BIGINT,
                ended_at BIGINT NOT NULL,
                duration_min INTEGER NOT NULL,
                created_at BIGINT NOT NULL
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_pomodoro_sessions_user_time ON pomodoro_sessions(username, ended_at)');

            await client.query(`CREATE TABLE IF NOT EXISTS pomodoro_daily_stats (
                username TEXT NOT NULL,
                date_key TEXT NOT NULL,
                work_sessions INTEGER NOT NULL DEFAULT 0,
                work_minutes INTEGER NOT NULL DEFAULT 0,
                break_minutes INTEGER NOT NULL DEFAULT 0,
                updated_at BIGINT NOT NULL,
                PRIMARY KEY (username, date_key)
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_pomodoro_daily_user_date ON pomodoro_daily_stats(username, date_key)');

            await client.query(`CREATE TABLE IF NOT EXISTS attachments (
                id TEXT PRIMARY KEY,
                owner_user_id TEXT NOT NULL,
                task_id TEXT NOT NULL,
                original_name TEXT NOT NULL,
                mime_type TEXT NOT NULL,
                size BIGINT NOT NULL,
                storage_driver TEXT NOT NULL,
                storage_path TEXT NOT NULL,
                created_at BIGINT NOT NULL
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_attachments_owner_task ON attachments(owner_user_id, task_id)');

            await client.query(`CREATE TABLE IF NOT EXISTS checklists (
                id SERIAL PRIMARY KEY,
                owner TEXT NOT NULL,
                name TEXT NOT NULL,
                created_at BIGINT NOT NULL,
                updated_at BIGINT NOT NULL
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_checklists_owner ON checklists(owner)');

            await client.query(`CREATE TABLE IF NOT EXISTS checklist_items (
                id SERIAL PRIMARY KEY,
                list_id INTEGER NOT NULL,
                owner TEXT NOT NULL,
                column_id INTEGER,
                title TEXT NOT NULL,
                tags_json TEXT,
                completed INTEGER NOT NULL DEFAULT 0,
                completed_by TEXT,
                subtasks_json TEXT,
                notes TEXT,
                created_at BIGINT NOT NULL,
                updated_at BIGINT NOT NULL,
                FOREIGN KEY(list_id) REFERENCES checklists(id) ON DELETE CASCADE
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_checklist_items_owner_list ON checklist_items(owner, list_id)');

            await client.query(`CREATE TABLE IF NOT EXISTS checklist_item_attachments (
                id TEXT PRIMARY KEY,
                list_id INTEGER NOT NULL,
                item_id INTEGER NOT NULL,
                uploader TEXT NOT NULL,
                original_name TEXT NOT NULL,
                mime_type TEXT NOT NULL,
                size BIGINT NOT NULL,
                storage_driver TEXT NOT NULL,
                storage_path TEXT NOT NULL,
                created_at BIGINT NOT NULL,
                FOREIGN KEY(list_id) REFERENCES checklists(id) ON DELETE CASCADE,
                FOREIGN KEY(item_id) REFERENCES checklist_items(id) ON DELETE CASCADE
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_checklist_item_attachments_item ON checklist_item_attachments(list_id, item_id, created_at)');

            await client.query(`CREATE TABLE IF NOT EXISTS checklist_columns (
                id SERIAL PRIMARY KEY,
                list_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at BIGINT NOT NULL,
                updated_at BIGINT NOT NULL,
                FOREIGN KEY(list_id) REFERENCES checklists(id) ON DELETE CASCADE
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_checklist_columns_list ON checklist_columns(list_id)');

            await client.query(`CREATE TABLE IF NOT EXISTS checklist_shares (
                id SERIAL PRIMARY KEY,
                list_id INTEGER NOT NULL,
                owner TEXT NOT NULL,
                shared_user TEXT NOT NULL,
                can_edit INTEGER NOT NULL DEFAULT 1,
                created_at BIGINT NOT NULL,
                UNIQUE(list_id, shared_user),
                FOREIGN KEY(list_id) REFERENCES checklists(id) ON DELETE CASCADE
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_checklist_shares_user ON checklist_shares(shared_user)');

            await client.query(`CREATE TABLE IF NOT EXISTS user_public_ids (
                user_key TEXT PRIMARY KEY,
                username TEXT NOT NULL UNIQUE,
                created_at BIGINT NOT NULL
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_user_public_ids_username ON user_public_ids(username)');

            await client.query(`CREATE TABLE IF NOT EXISTS checklist_share_invites (
                id SERIAL PRIMARY KEY,
                list_id INTEGER NOT NULL,
                inviter TEXT NOT NULL,
                invitee TEXT NOT NULL,
                role TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at BIGINT NOT NULL,
                updated_at BIGINT NOT NULL,
                expires_at BIGINT NOT NULL,
                responded_at BIGINT,
                FOREIGN KEY(list_id) REFERENCES checklists(id) ON DELETE CASCADE
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_checklist_invites_list ON checklist_share_invites(list_id, created_at)');
            await client.query('CREATE INDEX IF NOT EXISTS idx_checklist_invites_invitee ON checklist_share_invites(invitee, status, created_at)');

            await client.query(`CREATE TABLE IF NOT EXISTS checklist_audit_logs (
                id SERIAL PRIMARY KEY,
                list_id INTEGER NOT NULL,
                actor TEXT NOT NULL,
                type TEXT NOT NULL,
                target_type TEXT,
                target_id TEXT,
                data_json TEXT,
                created_at BIGINT NOT NULL,
                FOREIGN KEY(list_id) REFERENCES checklists(id) ON DELETE CASCADE
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_checklist_audit_list_time ON checklist_audit_logs(list_id, created_at)');
            await client.query('CREATE INDEX IF NOT EXISTS idx_checklist_audit_actor_time ON checklist_audit_logs(actor, created_at)');
            await client.query('CREATE INDEX IF NOT EXISTS idx_checklist_audit_time ON checklist_audit_logs(created_at)');

            await client.query(`CREATE TABLE IF NOT EXISTS user_notifications (
                id SERIAL PRIMARY KEY,
                username TEXT NOT NULL,
                type TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                data_json TEXT,
                created_at BIGINT NOT NULL,
                read_at BIGINT
            )`);
            await client.query('CREATE INDEX IF NOT EXISTS idx_user_notifications_user_time ON user_notifications(username, created_at)');
            await client.query('CREATE INDEX IF NOT EXISTS idx_user_notifications_user_read ON user_notifications(username, read_at)');

            await client.query('COMMIT');
        } catch (e) {
            try { await client.query('ROLLBACK'); } catch (rollbackErr) {}
            throw e;
        } finally {
            client.release();
        }
    })();
    return schemaInitPromise;
};

const getUpsertTarget = (table) => UPSERT_TARGETS[table] || null;

const rewriteInsertOrReplace = (sql) => {
    const trimmed = String(sql || '').trim();
    if (!/^INSERT\s+OR\s+REPLACE\s+INTO\s+/i.test(trimmed)) return sql;

    const match = trimmed.match(/^INSERT\s+OR\s+REPLACE\s+INTO\s+["`]?([a-zA-Z0-9_]+)["`]?\s*\(([^)]+)\)/i);
    if (!match) return sql;
    const table = match[1];
    const columns = match[2]
        .split(',')
        .map((col) => col.trim().replace(/^["`]|["`]$/g, ''))
        .filter(Boolean);

    const target = getUpsertTarget(table) || (columns.length ? [columns[0]] : null);
    if (!target || !target.length) return sql;

    const updateColumns = columns.filter((col) => !target.includes(col));
    const setClause = updateColumns.length
        ? updateColumns.map((col) => `${col} = EXCLUDED.${col}`).join(', ')
        : target.map((col) => `${col} = EXCLUDED.${col}`).join(', ');

    let rewritten = trimmed.replace(/INSERT\s+OR\s+REPLACE\s+INTO/i, 'INSERT INTO');
    const hasSemicolon = rewritten.endsWith(';');
    if (hasSemicolon) rewritten = rewritten.slice(0, -1);
    rewritten += ` ON CONFLICT (${target.join(', ')}) DO UPDATE SET ${setClause}`;
    if (hasSemicolon) rewritten += ';';
    return rewritten;
};

const rewritePlaceholders = (sql) => {
    const input = String(sql || '');
    let out = '';
    let index = 0;
    let inSingle = false;
    let inDouble = false;
    let inLineComment = false;
    let inBlockComment = false;

    for (let i = 0; i < input.length; i++) {
        const ch = input[i];
        const next = input[i + 1];

        if (inLineComment) {
            out += ch;
            if (ch === '\n') inLineComment = false;
            continue;
        }

        if (inBlockComment) {
            out += ch;
            if (ch === '*' && next === '/') {
                out += next;
                i++;
                inBlockComment = false;
            }
            continue;
        }

        if (inSingle) {
            out += ch;
            if (ch === "'" && next === "'") {
                out += next;
                i++;
                continue;
            }
            if (ch === "'") inSingle = false;
            continue;
        }

        if (inDouble) {
            out += ch;
            if (ch === '"' && next === '"') {
                out += next;
                i++;
                continue;
            }
            if (ch === '"') inDouble = false;
            continue;
        }

        if (ch === '-' && next === '-') {
            out += ch + next;
            i++;
            inLineComment = true;
            continue;
        }
        if (ch === '/' && next === '*') {
            out += ch + next;
            i++;
            inBlockComment = true;
            continue;
        }
        if (ch === "'") {
            out += ch;
            inSingle = true;
            continue;
        }
        if (ch === '"') {
            out += ch;
            inDouble = true;
            continue;
        }

        if (ch === '?') {
            index += 1;
            out += `$${index}`;
            continue;
        }

        out += ch;
    }

    return out;
};

const needsReturningId = (sql) => {
    const trimmed = String(sql || '').trim();
    if (!/^INSERT\b/i.test(trimmed)) return false;
    if (/\bRETURNING\b/i.test(trimmed)) return false;
    const match = trimmed.match(/^INSERT\s+INTO\s+["`]?([a-zA-Z0-9_]+)["`]?/i);
    if (!match) return false;
    return AUTO_ID_TABLES.has(match[1]);
};

const normalizeSql = (sql) => {
    let text = String(sql || '');
    text = rewriteInsertOrReplace(text);
    text = rewritePlaceholders(text);
    if (needsReturningId(text)) {
        const trimmed = text.trim();
        const hasSemicolon = trimmed.endsWith(';');
        const base = hasSemicolon ? trimmed.slice(0, -1) : trimmed;
        text = `${base} RETURNING id${hasSemicolon ? ';' : ''}`;
    }
    return text;
};

const normalizeRunArgs = (sql, params, callback) => {
    if (typeof params === 'function') return { sql, params: [], callback: params };
    return { sql, params: Array.isArray(params) ? params : [], callback };
};

const getTxState = () => txStorage.getStore() || null;

const transaction = async (fn) => {
    if (typeof fn !== 'function') throw new Error('transaction requires a function');
    await ensureSchema();

    const existing = getTxState();
    if (existing && existing.client) {
        const depth = (existing.depth || 1) + 1;
        const spName = `sp_${depth}`;
        await existing.client.query(`SAVEPOINT ${spName}`);
        try {
            const result = await txStorage.run({ client: existing.client, depth }, fn);
            await existing.client.query(`RELEASE SAVEPOINT ${spName}`);
            return result;
        } catch (e) {
            try {
                await existing.client.query(`ROLLBACK TO SAVEPOINT ${spName}`);
                await existing.client.query(`RELEASE SAVEPOINT ${spName}`);
            } catch (rollbackErr) {}
            throw e;
        }
    }

    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const result = await txStorage.run({ client, depth: 1 }, fn);
        await client.query('COMMIT');
        return result;
    } catch (e) {
        try { await client.query('ROLLBACK'); } catch (rollbackErr) {}
        throw e;
    } finally {
        client.release();
    }
};

const repairSequences = async () => {
    await ensureSchema();
    const tables = [
        'checklists',
        'checklist_items',
        'checklist_columns',
        'checklist_shares',
        'checklist_share_invites',
        'checklist_audit_logs',
        'user_notifications',
        'pomodoro_sessions'
    ];

    for (const table of tables) {
        const result = await query(`SELECT MAX(id) AS max_id FROM ${table}`);
        const maxId = result && result.rows && result.rows[0] ? Number(result.rows[0].max_id) : 0;
        if (Number.isFinite(maxId) && maxId > 0) {
            await query(`SELECT setval(pg_get_serial_sequence('${table}', 'id'), ${maxId}, true)`);
        } else {
            await query(`SELECT setval(pg_get_serial_sequence('${table}', 'id'), 1, false)`);
        }
    }
};

const query = async (sql, params) => {
    await ensureSchema();
    const text = normalizeSql(sql);
    const existing = getTxState();
    const executor = existing && existing.client ? existing.client : pool;
    return executor.query(text, Array.isArray(params) ? params : []);
};

const run = (sql, params, callback) => {
    const { sql: rawSql, params: values, callback: cb } = normalizeRunArgs(sql, params, callback);
    const done = typeof cb === 'function' ? cb : () => {};

    query(rawSql, values)
        .then((result) => {
            const ctx = {
                changes: result && typeof result.rowCount === 'number' ? result.rowCount : 0,
                lastID: result && result.rows && result.rows[0] && result.rows[0].id !== undefined ? result.rows[0].id : undefined
            };
            done.call(ctx, null);
        })
        .catch((err) => done.call({ changes: 0, lastID: undefined }, err));
};

const get = (sql, params, callback) => {
    const { sql: rawSql, params: values, callback: cb } = normalizeRunArgs(sql, params, callback);
    if (typeof cb !== 'function') return;
    query(rawSql, values)
        .then((result) => cb(null, (result && result.rows && result.rows[0]) || undefined))
        .catch((err) => cb(err));
};

const all = (sql, params, callback) => {
    const { sql: rawSql, params: values, callback: cb } = normalizeRunArgs(sql, params, callback);
    if (typeof cb !== 'function') return;
    query(rawSql, values)
        .then((result) => cb(null, (result && result.rows) || []))
        .catch((err) => cb(err));
};

// sqlite3 compatibility shim: call fn immediately.
const serialize = (fn) => {
    if (typeof fn === 'function') fn();
};

module.exports = { run, get, all, serialize };
module.exports.transaction = transaction;
module.exports.repairSequences = repairSequences;
