/**
 * EXAMPLE — copy to `src/test/preload.ts` in the consuming repo and delete the
 * clients it does not have. `bunfig.toml` in this repo already wires it via
 * `preload`.
 *
 * This file exists because breaking the rule it encodes is expensive: a unit
 * test that mocks a third-party SDK in its own file can lose a registry race
 * and issue a REAL API call to the provider. `mock.module` mutates a module
 * registry shared by every test file in the run, so two files mocking the same
 * module is last-write-wins — and the file that loses silently inherits the
 * other's mock. Per-file mocking of an external client is therefore not a style
 * preference; it is a correctness hazard.
 *
 * Every client is steered through an exported `<client>Control` object and reset
 * by `resetExternalMocks()`. A test changes behaviour by assigning to a control,
 * never by calling `mock.module` itself.
 *
 * The db stand-in is a Proxy rather than an object with a literal `then`,
 * because `unicorn/no-thenable` rejects the latter — and it is right to: an
 * accidental `await` on a thenable object resolves to something surprising.
 * Here the thenable behaviour is deliberate, which is exactly the case the
 * Proxy expresses without tripping the rule.
 */

import { mock } from 'bun:test';

/* ── Redis ─────────────────────────────────────────────────────────────── */

export const redisControl = {
  /** Current request count in the window, as `rate-limit.middleware.ts` reads it. */
  get: async (_key: string): Promise<string | null> => '0',
  ping: async (): Promise<string> => 'PONG',
};

/* `new Redis(url)` connects on construction, and `src/queues/index.ts` hands
   that same client to BullMQ — so importing the real module opens a socket and
   starts a queue the unit tier must never start. */
void mock.module('../lib/redis/redis.ts', () => ({
  redis: {
    get: (key: string) => redisControl.get(key),
    ping: () => redisControl.ping(),
    multi: () => ({ incr: () => {}, pexpire: () => {}, exec: async () => [] }),
  },
}));

/* ── Queues ────────────────────────────────────────────────────────────── */

export type QueuedJob = { queue: string; name: string; data: unknown };

/** Every job published during a test, in call order. */
export const queuedJobs: QueuedJob[] = [];

/* Refuses the custom job ids BullMQ refuses (its Job.validateOptions), so a producer
   that could never enqueue fails here instead of passing:
   .claude/anti-patterns/queue-job-id-cannot-contain-colon.md. */
function assertJobId(jobId: string): void {
  if (`${Number.parseInt(jobId, 10)}` === jobId) throw new Error('Custom Id cannot be integers');
  if (jobId.includes(':') && jobId.split(':').length !== 3) {
    throw new Error('Custom Id cannot contain :');
  }
}

function createQueueMock(queue: string) {
  return {
    add: async (name: string, data: unknown, opts: { jobId?: string } = {}) => {
      if (opts.jobId !== undefined) assertJobId(opts.jobId);
      queuedJobs.push({ queue, name, data });
      return { id: opts.jobId ?? `${queue}-job-1` };
    },
  };
}

void mock.module('../queues/index.ts', () => ({
  emailQueue: createQueueMock('email'),
  notificationQueue: createQueueMock('notification'),
}));

/* ── Better Auth ───────────────────────────────────────────────────────── */

export type FakeSession = { user: { id: string; email: string; role?: string } } | null;

export const authControl = {
  /** What `auth.api.getSession` resolves with. `null` means unauthenticated. */
  session: null as FakeSession,
  getSession: async (): Promise<FakeSession> => authControl.session,
};

void mock.module('../lib/auth/auth.ts', () => ({
  auth: {
    api: { getSession: () => authControl.getSession() },
    /* better-auth's own catch-all route handler, proxied by
       `modules/auth/auth.handler.ts`. It owns its response shape; this repo
       only forwards the raw Request to it. */
    handler: async () =>
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
  },
}));

/* ── A third-party provider SDK ────────────────────────────────────────── */

/* One section per external provider (mail, search, object storage, …). Rename
   `<provider-sdk>` to the npm package your `src/lib/<provider>/<provider>.ts`
   wrapper imports, and shape the fake after the calls that wrapper actually makes. */

export type ProviderRequest = { operation: string; payload: unknown };

/** Every request handed to the provider SDK, in call order. */
export const providerCalls: ProviderRequest[] = [];

export const providerControl = {
  send: async (_request: ProviderRequest): Promise<{ data?: unknown; error?: unknown }> => ({
    data: { id: 'req_1' },
  }),
};

/* The npm package is mocked rather than the repo's wrapper around it, so that
   wrapper — the part with branches worth testing — still runs for real. */
void mock.module('<provider-sdk>', () => ({
  ProviderClient: class {
    send = (request: ProviderRequest) => {
      providerCalls.push(request);
      return providerControl.send(request);
    };
  },
}));

/* ── Clients that connect at module load ───────────────────────────────── */

/* None of these is exercised by the unit tier; they are replaced so that
   importing `app.ts` — which reaches them transitively through the modules —
   cannot open a socket or read a real credential. Add one line per client. */
void mock.module('../lib/storage/storage.ts', () => ({ s3Client: {} }));

/* ── Postgres ──────────────────────────────────────────────────────────── */

export const dbControl = {
  /** Rows the next terminal query resolves with. */
  rows: [] as unknown[],
  execute: async (): Promise<unknown> => undefined,
};

/** What each builder link was handed, so a test can assert on the statement
 * being built rather than on a round trip the unit tier never makes. */
export const dbCalls: { values: unknown[]; set: unknown[]; limit: number[] } = {
  values: [],
  set: [],
  limit: [],
};

/* A fluent stand-in for Drizzle's builder. Implemented as a Proxy rather than
   an object literal with a `then` key: a literal `then` makes the object
   thenable, which `unicorn/no-thenable` rejects because an accidental `await`
   on it resolves to something surprising. Here the thenable behaviour is
   deliberate — awaiting the chain is exactly how the repositories consume it. */
const dbChain: Record<string, unknown> = new Proxy(
  {},
  {
    get(_target, prop) {
      if (prop === 'then') {
        return (resolve: (value: unknown) => unknown) => resolve(dbControl.rows);
      }
      if (prop === 'execute') return () => dbControl.execute();
      if (prop === 'values') {
        return (row: unknown) => {
          dbCalls.values.push(row);
          return dbChain;
        };
      }
      if (prop === 'set') {
        return (row: unknown) => {
          dbCalls.set.push(row);
          return dbChain;
        };
      }
      if (prop === 'limit') {
        return (n: number) => {
          dbCalls.limit.push(n);
          return dbChain;
        };
      }
      /* Every other builder link (select, from, where, orderBy, insert,
         returning, update, …) just continues the chain. */
      return () => dbChain;
    },
  },
);

void mock.module('../db/client/index.ts', () => ({
  db: Object.assign(dbChain, {
    transaction: async (fn: (tx: unknown) => unknown) => fn(dbChain),
  }),
  client: {},
}));

/* ── Reset ─────────────────────────────────────────────────────────────── */

/** Call from `beforeEach` so one test's steering cannot leak into the next. */
export function resetExternalMocks(): void {
  providerCalls.length = 0;
  queuedJobs.length = 0;
  dbCalls.values.length = 0;
  dbCalls.set.length = 0;
  dbCalls.limit.length = 0;
  providerControl.send = async () => ({ data: { id: 'req_1' } });
  redisControl.get = async () => '0';
  redisControl.ping = async () => 'PONG';
  dbControl.rows = [];
  dbControl.execute = async () => undefined;
  authControl.session = null;
  authControl.getSession = async () => authControl.session;
}
