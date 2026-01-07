const driver = String(process.env.DB_DRIVER || '').trim().toLowerCase();
const hasPostgresEnv = Boolean(process.env.DATABASE_URL || process.env.PGHOST || process.env.PGDATABASE);

if (driver === 'sqlite') {
    module.exports = require('./db_sqlite');
} else if (driver === 'postgres' || hasPostgresEnv) {
    module.exports = require('./db_postgres');
} else {
    module.exports = require('./db_sqlite');
}

