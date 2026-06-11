#!/usr/bin/env node
/**
 * Stateful local finAPI mock for lifecycle/cleanup QA (calytics-cli tool).
 *
 * Faithful behaviors under test:
 *  - per-user deletion via user-token DELETE /api/v2/users (423/401 fault injection)
 *  - mandatorAdmin getUserList with isDeleted filter + GDPR id-masking of deleted users
 *  - mandatorAdmin batch deleteUsers (unknown ids silently ignored)
 *  - OAuth password + client_credentials grants; every call audited with the
 *    client_id used, so tests can assert mandator routing (M1 vs M2 creds).
 *
 * Test-control endpoints: GET /__state, POST /__seed, POST /__reset, POST /__faults.
 * Fault conventions (no /__faults needed): user id containing '-locked' -> 423 on
 * delete; '-gone' -> 401 on delete (user "already deleted" at vendor).
 *
 * Start: node finapi-mock-server.js [port]   (default 4010)
 */
const http = require('http');
const { URL } = require('url');

const PORT = parseInt(process.argv[2] ?? '4010', 10);

const state = {
    users: new Map(), // id -> {id, password, registrationDate, deleted, createdByClientId, mandator}
    tokens: new Map(), // token -> {kind:'client'|'user', clientId?, userId?}
    audit: [], // {ts, method, path, clientId, userId, grant, body}
    faults: {}, // userId -> statusCode for DELETE
};

// client_id -> mandator label, mirrors the local secret seeded by the QA run
const MANDATOR_BY_CLIENT = {
    'admin-m2-client-id': 2,
    'admin-m1-client-id': 1,
    '454ecb6c-0ee4-4505-a7f5-ca9907366eee': 1, // regular fallback client (M1 in prod topology)
};

function gdprMask(id) {
    if (id.length <= 2) return id;
    return id[0] + 'X'.repeat(id.length - 2) + id[id.length - 1];
}

function readBody(req) {
    return new Promise((resolve) => {
        let data = '';
        req.on('data', (c) => (data += c));
        req.on('end', () => resolve(data));
    });
}

function parseForm(body, contentType) {
    if (contentType?.includes('json')) {
        try { return JSON.parse(body || '{}'); } catch { return {}; }
    }
    return Object.fromEntries(new URLSearchParams(body));
}

function json(res, code, obj) {
    res.writeHead(code, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(obj));
}

function principal(req) {
    const auth = req.headers.authorization ?? '';
    const token = auth.replace(/^Bearer\s+/i, '');
    return state.tokens.get(token);
}

const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, `http://localhost:${PORT}`);
    const body = await readBody(req);
    const who = principal(req);
    state.audit.push({
        ts: Date.now(),
        method: req.method,
        path: url.pathname,
        clientId: who?.clientId,
        userId: who?.userId,
    });

    // ── test control ────────────────────────────────────────────────────────
    if (url.pathname === '/__state') {
        return json(res, 200, {
            users: [...state.users.values()],
            audit: state.audit,
            faults: state.faults,
        });
    }
    if (url.pathname === '/__reset') {
        state.users.clear();
        state.tokens.clear();
        state.audit.length = 0;
        state.faults = {};
        return json(res, 200, { ok: true });
    }
    if (url.pathname === '/__seed' && req.method === 'POST') {
        const { users = [] } = JSON.parse(body || '{}');
        for (const u of users) {
            state.users.set(u.id, {
                id: u.id,
                password: u.password ?? 'pw',
                registrationDate: u.registrationDate ?? new Date().toISOString().slice(0, 10),
                deleted: u.deleted ?? false,
                createdByClientId: u.createdByClientId ?? 'seed',
            });
        }
        return json(res, 200, { ok: true, count: users.length });
    }
    if (url.pathname === '/__faults' && req.method === 'POST') {
        state.faults = JSON.parse(body || '{}');
        return json(res, 200, { ok: true });
    }

    // ── oauth ───────────────────────────────────────────────────────────────
    if (url.pathname === '/api/v2/oauth/token' && req.method === 'POST') {
        const form = parseForm(body, req.headers['content-type']);
        if (form.grant_type === 'client_credentials') {
            const token = `tok-client-${form.client_id}-${state.audit.length}`;
            state.tokens.set(token, { kind: 'client', clientId: form.client_id });
            state.audit[state.audit.length - 1].clientId = form.client_id;
            state.audit[state.audit.length - 1].grant = 'client_credentials';
            return json(res, 200, { access_token: token, token_type: 'bearer', expires_in: 3600, scope: 'all' });
        }
        if (form.grant_type === 'password') {
            const user = state.users.get(form.username);
            state.audit[state.audit.length - 1].grant = 'password';
            state.audit[state.audit.length - 1].userId = form.username;
            state.audit[state.audit.length - 1].clientId = form.client_id;
            if (!user || user.deleted || user.password !== form.password) {
                return json(res, 400, { errors: [{ code: 'UNAUTHORIZED_ACCESS', message: 'Invalid user credentials' }] });
            }
            const token = `tok-user-${form.username}`;
            state.tokens.set(token, { kind: 'user', userId: form.username, clientId: form.client_id });
            return json(res, 200, { access_token: token, token_type: 'bearer', expires_in: 3600, refresh_token: 'r', scope: 'all' });
        }
        return json(res, 400, { errors: [{ code: 'BAD_REQUEST', message: 'unknown grant' }] });
    }

    // ── user create / delete ────────────────────────────────────────────────
    if (url.pathname === '/api/v2/users' && req.method === 'POST') {
        const payload = parseForm(body, 'json');
        const id = payload.id ?? `random-${Date.now()}`;
        const password = `pw-${id}`;
        state.users.set(id, {
            id,
            password,
            registrationDate: new Date().toISOString().slice(0, 10),
            deleted: false,
            createdByClientId: who?.clientId ?? 'unknown',
        });
        return json(res, 201, { id, password, email: payload.email, phone: payload.phone });
    }
    if (url.pathname === '/api/v2/users' && req.method === 'DELETE') {
        if (!who || who.kind !== 'user') {
            return json(res, 401, { errors: [{ code: 'UNAUTHORIZED_ACCESS', message: 'invalid token' }] });
        }
        const user = state.users.get(who.userId);
        const fault = state.faults[who.userId] ?? (who.userId.includes('-locked') ? 423 : undefined);
        if (fault) return json(res, fault, { errors: [{ code: fault === 423 ? 'LOCKED' : 'ERROR', message: `fault ${fault}` }] });
        if (!user || user.deleted) {
            return json(res, 401, { errors: [{ code: 'UNAUTHORIZED_ACCESS', message: 'user gone' }] });
        }
        user.deleted = true;
        user.deletedByClientId = who.clientId;
        return json(res, 200, {});
    }

    // ── mandator admin ──────────────────────────────────────────────────────
    if (url.pathname === '/api/v2/mandatorAdmin/getUserList' && req.method === 'GET') {
        const page = parseInt(url.searchParams.get('page') ?? '1', 10);
        const perPage = parseInt(url.searchParams.get('perPage') ?? '20', 10);
        const isDeletedParam = url.searchParams.get('isDeleted'); // null = no filter (returns BOTH, deleted masked)
        let users = [...state.users.values()];
        if (isDeletedParam === 'false') users = users.filter((u) => !u.deleted);
        if (isDeletedParam === 'true') users = users.filter((u) => u.deleted);
        const slice = users.slice((page - 1) * perPage, page * perPage).map((u) => ({
            userId: u.deleted ? gdprMask(u.id) : u.id,
            registrationDate: u.registrationDate,
        }));
        return json(res, 200, { users: slice });
    }
    if (url.pathname === '/api/v2/mandatorAdmin/deleteUsers' && req.method === 'POST') {
        const { userIds = [] } = parseForm(body, 'json');
        for (const id of userIds) {
            const u = state.users.get(id);
            if (u) { u.deleted = true; u.deletedByClientId = who?.clientId; } // unknown ids silently ignored
        }
        return json(res, 200, {});
    }

    // ── webforms (eager-creation flow checks) ───────────────────────────────
    if (url.pathname === '/api/webForms/bankConnectionImport' && req.method === 'POST') {
        const id = `mock-wf-${Date.now()}`;
        return json(res, 201, { id, url: `http://localhost:${PORT}/webform/${id}`, expiresAt: new Date(Date.now() + 30 * 60 * 1000).toISOString() });
    }
    if (url.pathname.startsWith('/api/webForms/')) {
        return json(res, 200, { id: url.pathname.split('/').pop(), status: 'NOT_YET_OPENED', payload: {} });
    }

    json(res, 404, { errors: [{ code: 'NOT_FOUND', message: url.pathname }] });
});

server.listen(PORT, () => console.log(`finapi-mock listening on :${PORT}`));
