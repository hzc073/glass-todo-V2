const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const crypto = require('crypto');

const dbFile = process.env.DB_PATH || path.join(__dirname, '../database.sqlite');
const db = new sqlite3.Database(dbFile);

// 初始化数据库表结构
db.serialize(() => {
    // 用户表
    db.run(`CREATE TABLE IF NOT EXISTS users (
        username TEXT PRIMARY KEY,
        password TEXT,
        is_admin INTEGER DEFAULT 0
    )`);

    // 数据表
    db.run(`CREATE TABLE IF NOT EXISTS data (
        username TEXT PRIMARY KEY,
        json_data TEXT,
        version INTEGER
    )`);

    // v2 tasks table
    db.run(`CREATE TABLE IF NOT EXISTS tasks_v2 (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        title TEXT NOT NULL,
        notes TEXT,
        status TEXT NOT NULL,
        due_date TEXT,
        start_time TEXT,
        end_time TEXT,
        tags_json TEXT,
        subtasks_json TEXT,
        attachments_json TEXT,
        inbox INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0,
        remind_at INTEGER,
        repeat_rule TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
    )`);
    db.run("CREATE INDEX IF NOT EXISTS idx_tasks_v2_user_updated ON tasks_v2(username, updated_at)");
    db.run("CREATE INDEX IF NOT EXISTS idx_tasks_v2_user_due ON tasks_v2(username, due_date)");

    // v2 time tracking
    db.run(`CREATE TABLE IF NOT EXISTS time_activities (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        task_id TEXT,
        name TEXT NOT NULL,
        icon TEXT,
        color TEXT,
        category TEXT,
        goal TEXT,
        note TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
    )`);
    db.run("CREATE INDEX IF NOT EXISTS idx_time_activities_user ON time_activities(username, updated_at)");
    db.run("CREATE INDEX IF NOT EXISTS idx_time_activities_task ON time_activities(task_id)");

    db.run(`CREATE TABLE IF NOT EXISTS time_entries (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        activity_id TEXT NOT NULL,
        task_id TEXT,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        duration_ms INTEGER,
        note TEXT,
        tags_json TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
    )`);
    db.run("CREATE INDEX IF NOT EXISTS idx_time_entries_user_time ON time_entries(username, started_at)");
    db.run("CREATE INDEX IF NOT EXISTS idx_time_entries_activity ON time_entries(activity_id)");

    // 设置表
    db.run(`CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS user_settings (
        username TEXT PRIMARY KEY,
        settings_json TEXT,
        updated_at INTEGER NOT NULL
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS push_subscriptions (
        endpoint TEXT PRIMARY KEY,
        username TEXT,
        p256dh TEXT,
        auth TEXT,
        expiration_time INTEGER,
        created_at INTEGER
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS pomodoro_settings (
        username TEXT PRIMARY KEY,
        work_min INTEGER NOT NULL,
        short_break_min INTEGER NOT NULL,
        long_break_min INTEGER NOT NULL,
        long_break_every INTEGER NOT NULL,
        auto_start_next INTEGER NOT NULL DEFAULT 0,
        auto_start_break INTEGER NOT NULL DEFAULT 0,
        auto_start_work INTEGER NOT NULL DEFAULT 0,
        auto_finish_task INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS pomodoro_state (
        username TEXT PRIMARY KEY,
        mode TEXT NOT NULL,
        remaining_ms INTEGER NOT NULL,
        is_running INTEGER NOT NULL,
        target_end INTEGER,
        cycle_count INTEGER NOT NULL DEFAULT 0,
        current_task_id INTEGER,
        updated_at INTEGER NOT NULL
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS pomodoro_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        task_id INTEGER,
        task_title TEXT,
        started_at INTEGER,
        ended_at INTEGER NOT NULL,
        duration_min INTEGER NOT NULL,
        created_at INTEGER NOT NULL
    )`);

    db.run("CREATE INDEX IF NOT EXISTS idx_pomodoro_sessions_user_time ON pomodoro_sessions(username, ended_at)");

    db.run(`CREATE TABLE IF NOT EXISTS pomodoro_daily_stats (
        username TEXT NOT NULL,
        date_key TEXT NOT NULL,
        work_sessions INTEGER NOT NULL DEFAULT 0,
        work_minutes INTEGER NOT NULL DEFAULT 0,
        break_minutes INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (username, date_key)
    )`);

    db.run("CREATE INDEX IF NOT EXISTS idx_pomodoro_daily_user_date ON pomodoro_daily_stats(username, date_key)");

    db.run(`CREATE TABLE IF NOT EXISTS attachments (
        id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
        task_id INTEGER NOT NULL,
        original_name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size INTEGER NOT NULL,
        storage_driver TEXT NOT NULL,
        storage_path TEXT NOT NULL,
        created_at INTEGER NOT NULL
    )`);

    db.run("CREATE INDEX IF NOT EXISTS idx_attachments_owner_task ON attachments(owner_user_id, task_id)");

    db.run(`CREATE TABLE IF NOT EXISTS checklists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner TEXT NOT NULL,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
    )`);
    db.run("CREATE INDEX IF NOT EXISTS idx_checklists_owner ON checklists(owner)");

    db.run(`CREATE TABLE IF NOT EXISTS checklist_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        list_id INTEGER NOT NULL,
        owner TEXT NOT NULL,
        column_id INTEGER,
        title TEXT NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0,
        completed_by TEXT,
        subtasks_json TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(list_id) REFERENCES checklists(id) ON DELETE CASCADE
    )`);
    db.run("CREATE INDEX IF NOT EXISTS idx_checklist_items_owner_list ON checklist_items(owner, list_id)");

    db.run(`CREATE TABLE IF NOT EXISTS checklist_columns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        list_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(list_id) REFERENCES checklists(id) ON DELETE CASCADE
    )`);
    db.run("CREATE INDEX IF NOT EXISTS idx_checklist_columns_list ON checklist_columns(list_id)");

    db.run(`CREATE TABLE IF NOT EXISTS checklist_shares (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        list_id INTEGER NOT NULL,
        owner TEXT NOT NULL,
        shared_user TEXT NOT NULL,
        can_edit INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        UNIQUE(list_id, shared_user),
        FOREIGN KEY(list_id) REFERENCES checklists(id) ON DELETE CASCADE
    )`);
    db.run("CREATE INDEX IF NOT EXISTS idx_checklist_shares_user ON checklist_shares(shared_user)");
    
    // 自动迁移：检查 is_admin 字段
    db.all("PRAGMA table_info(users)", (err, rows) => {
        if (!rows.some(r => r.name === 'is_admin')) {
            console.log(">> DB Migration: Adding is_admin column...");
            db.run("ALTER TABLE users ADD COLUMN is_admin INTEGER DEFAULT 0");
        }
    });

    db.all("PRAGMA table_info(pomodoro_settings)", (err, rows) => {
        if (!rows) return;
        if (!rows.some(r => r.name === 'auto_start_break')) {
            console.log(">> DB Migration: Adding pomodoro_settings.auto_start_break column...");
            db.run("ALTER TABLE pomodoro_settings ADD COLUMN auto_start_break INTEGER NOT NULL DEFAULT 0");
        }
        if (!rows.some(r => r.name === 'auto_start_work')) {
            console.log(">> DB Migration: Adding pomodoro_settings.auto_start_work column...");
            db.run("ALTER TABLE pomodoro_settings ADD COLUMN auto_start_work INTEGER NOT NULL DEFAULT 0");
        }
        if (!rows.some(r => r.name === 'auto_finish_task')) {
            console.log(">> DB Migration: Adding pomodoro_settings.auto_finish_task column...");
            db.run("ALTER TABLE pomodoro_settings ADD COLUMN auto_finish_task INTEGER NOT NULL DEFAULT 0");
        }
    });

    db.all("PRAGMA table_info(tasks_v2)", (err, rows) => {
        if (!rows) return;
        if (!rows.some(r => r.name === 'subtasks_json')) {
            console.log(">> DB Migration: Adding tasks_v2.subtasks_json column...");
            db.run("ALTER TABLE tasks_v2 ADD COLUMN subtasks_json TEXT");
        }
        if (!rows.some(r => r.name === 'attachments_json')) {
            console.log(">> DB Migration: Adding tasks_v2.attachments_json column...");
            db.run("ALTER TABLE tasks_v2 ADD COLUMN attachments_json TEXT");
        }
    });

    db.all("PRAGMA table_info(time_activities)", (err, rows) => {
        if (!rows) return;
        if (!rows.some(r => r.name === 'icon')) {
            console.log(">> DB Migration: Adding time_activities.icon column...");
            db.run("ALTER TABLE time_activities ADD COLUMN icon TEXT");
        }
        if (!rows.some(r => r.name === 'category')) {
            console.log(">> DB Migration: Adding time_activities.category column...");
            db.run("ALTER TABLE time_activities ADD COLUMN category TEXT");
        }
        if (!rows.some(r => r.name === 'goal')) {
            console.log(">> DB Migration: Adding time_activities.goal column...");
            db.run("ALTER TABLE time_activities ADD COLUMN goal TEXT");
        }
        if (!rows.some(r => r.name === 'note')) {
            console.log(">> DB Migration: Adding time_activities.note column...");
            db.run("ALTER TABLE time_activities ADD COLUMN note TEXT");
        }
    });

    db.all("PRAGMA table_info(time_entries)", (err, rows) => {
        if (!rows) return;
        if (!rows.some(r => r.name === 'tags_json')) {
            console.log(">> DB Migration: Adding time_entries.tags_json column...");
            db.run("ALTER TABLE time_entries ADD COLUMN tags_json TEXT");
        }
    });

    db.all("PRAGMA table_info(checklist_items)", (err, rows) => {
        if (!rows) return;
        if (!rows.some(r => r.name === 'completed_by')) {
            console.log(">> DB Migration: Adding checklist_items.completed_by column...");
            db.run("ALTER TABLE checklist_items ADD COLUMN completed_by TEXT");
        }
        if (!rows.some(r => r.name === 'column_id')) {
            console.log(">> DB Migration: Adding checklist_items.column_id column...");
            db.run("ALTER TABLE checklist_items ADD COLUMN column_id INTEGER");
        }
        if (!rows.some(r => r.name === 'subtasks_json')) {
            console.log(">> DB Migration: Adding checklist_items.subtasks_json column...");
            db.run("ALTER TABLE checklist_items ADD COLUMN subtasks_json TEXT");
        }
        if (!rows.some(r => r.name === 'notes')) {
            console.log(">> DB Migration: Adding checklist_items.notes column...");
            db.run("ALTER TABLE checklist_items ADD COLUMN notes TEXT");
        }
    });

    db.all("PRAGMA table_info(checklist_shares)", (err, rows) => {
        if (!rows) return;
        if (!rows.some(r => r.name === 'can_edit')) {
            console.log(">> DB Migration: Adding checklist_shares.can_edit column...");
            db.run("ALTER TABLE checklist_shares ADD COLUMN can_edit INTEGER NOT NULL DEFAULT 1");
        }
    });
});

module.exports = db;
