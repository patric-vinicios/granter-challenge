# Api

JSON API for the chat application, built with Phoenix 1.8 on Elixir 1.20 and
PostgreSQL 16. There is no HTML layer: every response is JSON, including
errors.

## Running with Docker

The only prerequisite is Docker with Compose v2.

```sh
cp .env.example .env
docker compose -f docker-compose.dev.yml up
```

The database starts first, the API waits for it to pass its healthcheck, then
creates the database, runs migrations and seeds, and serves on port 4000.

```sh
curl localhost:4000/api/health
# {"status":"ok","database":"up"}
```

## Running natively

Requires Elixir 1.20 with Erlang/OTP 29. Start only the database from the same
Compose file, then run the app on the host:

```sh
docker compose -f docker-compose.dev.yml up postgres-dev

cp .env.example .env
set -a; source .env; set +a   # the app reads its configuration from the environment

mix setup
mix phx.server
```

Sourcing `.env` is not optional: startup aborts naming any missing secret, in
every environment except `test`.

## Seeded accounts

`mix ecto.setup` (and the Docker startup) populate the database with seven demo
accounts, a full contact graph between them, four private conversations and two
groups, so the application looks lived-in on first run. Every account shares the
same password:

| `@username` | Name | Password |
|---|---|---|
| `@demo` | Usuário Demo | `senha123` |
| `@anabeatriz` | Ana Beatriz | `senha123` |
| `@carlosedu` | Carlos Eduardo | `senha123` |
| `@joaopedro` | João Pedro | `senha123` |
| `@leticiam` | Letícia Moraes | `senha123` |
| `@marianas` | Mariana Silva | `senha123` |
| `@rafaelalves` | Rafael Alves | `senha123` |

`@demo` is the account to log in with first: it belongs to every conversation
and creates both groups, so every endpoint is exercisable from it. The seed
script is idempotent — re-running it prints `Seeds already applied, skipping`
and changes nothing — and refuses to run in the `prod` environment.

## Tests

The test suite has its own database, on a different port, so running it never
touches the data you are looking at in development:

```sh
docker compose -f docker-compose.test.yml up -d
mix test
```

`mix test` needs no environment variables at all.

Before committing, run the full gate — compile with warnings as errors,
unused-dependency check, formatter, Credo and coverage:

```sh
mix precommit
```

### Static analysis

Every public function in `lib/` carries an `@spec`, and each Ecto schema a
`t/0`, so Dialyzer checks the whole application surface. Behaviour callbacks
(`@impl`) are typed by the behaviour itself and are deliberately left without a
redundant spec.

```sh
mix dialyzer
```

Dialyzer is kept out of `mix precommit` on purpose: the first run builds a PLT
and costs minutes, while the rest of the gate finishes in seconds. The PLT is
cached in `priv/plts/` (git-ignored), so later runs take a few seconds and only
a dependency or Erlang/Elixir upgrade pays the build again. `.dialyzer_ignore.exs`
holds a single documented entry for an upstream `Ecto.Multi`/`MapSet` opacity
false positive.

## Environment variables

`.env.example` carries a working default for each one.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `DATABASE_URL` | no | credentials in `config/dev.exs` | Overrides the per-environment database connection. Set by the `api` container to reach `postgres-dev` by service name. |
| `SECRET_KEY_BASE` | yes, outside `test` | — | Signs and encrypts Phoenix payloads. Generate with `mix phx.gen.secret`. |
| `JWT_SECRET` | yes, outside `test` | — | Signs the bearer tokens issued by the authentication endpoints. Generate with `mix phx.gen.secret`. |
| `PORT` | no | `4000` | Port the endpoint listens on. |
| `BIND_IP` | no | `127.0.0.1` | Interface to bind. `0.0.0.0` inside a container so the published port is reachable. |
| `CORS_ORIGINS` | no | `http://localhost:5173,http://localhost:3000` | Comma-separated browser origins allowed to call the API. |

## Error format

Every non-2xx response, from any endpoint, has the same shape. Clients branch
on `errors.code` and can display `errors.detail` as-is. `fields` appears only
on validation failures (422).

```json
{
  "errors": {
    "code": "validation_error",
    "detail": "The request could not be processed",
    "fields": {
      "username": ["has already been taken"]
    }
  }
}
```

## API reference

Every REST endpoint, the full WebSocket contract and the complete error-code
table are documented in [`docs/api.md`](docs/api.md), with a copy-pasteable
request and a concrete response body for each. The channel topics and events —
which the router cannot reveal — are there too.

## Design decisions

**JWT over cookie sessions.** The client is a separate-origin SPA and, more
importantly, the same credential has to authenticate a `WebSocket`, which cannot
carry a cookie the way an `XHR` does and cannot participate in CSRF-token
handshakes. A stateless bearer token is presented identically as an
`Authorization` header for HTTP and as the `token` connect param for the socket:
one credential, one verification path, no cross-origin cookie or CSRF machinery.

**Argon2id over bcrypt.** Argon2id is memory-hard, so it resists GPU and ASIC
cracking that bcrypt's CPU-bound work does not. It also avoids bcrypt's silent
truncation of passwords past 72 bytes, which turns a longer passphrase into a
weaker secret than the user believes. The published 8–72 character contract is a
stable API promise, not a technical limit of the algorithm.

**REST plus Channels, not all-channel and not GraphQL.** Request/response
resources — register, contacts, history pagination — are a natural fit for REST
and stay cacheable, debuggable with `curl`, and trivial to document. Real-time
fan-out is the one thing REST cannot do without polling, so it lives on Phoenix
Channels over PubSub, where a message is written once and pushed to every
participant. Routing everything through channels would reinvent HTTP semantics
over a socket; GraphQL would add a schema layer and resolver N+1 risk with no
gain for a fixed, small contract.

**A single `conversations` table for private and group.** Both are the same
thing — a set of participants exchanging messages — distinguished by a `type`
column, with `name`/`creator_id` null for private conversations. This lets one
`conversation_participants` table, one `messages` foreign key, one authorization
predicate (`Conversations.participant?/2`) and one history query serve both
kinds. Two separate tables would duplicate every one of those and force a union
at read time.

**Keyset over offset pagination.** History is anchored on `(inserted_at, id)`
cursors rather than `LIMIT/OFFSET`. In a live chat new messages arrive mid-scroll
constantly; offset pagination shifts and duplicates rows whenever that happens,
and its cost grows with the offset. A keyset cursor is stable under concurrent
inserts and reads the same supporting index in constant time no matter how deep
the client has scrolled.

**Unidirectional contacts.** Adding a contact affects only the caller's list; the
target is neither notified nor modified. This keeps the model simple and matches
the product: you can message someone who added you even if you have not added
them back (the recipient of a private conversation always sees it), while the
contact requirement is enforced only on the side that *initiates* a conversation
or builds a group.

## What I would do differently with more time

- **Token revocation and login rate limiting.** The JWT is stateless and not
  revocable before `exp`; a logout endpoint backed by an ETS `jti` denylist, plus
  per-IP and per-username login throttling, are specified but not yet built.
- **Machine-readable schema.** `docs/api.md` is hand-authored Markdown. An
  OpenAPI document generated from the response views (or a contract test that
  fails when a documented example drifts from an assertion) would keep the docs
  honest automatically instead of by review.
- **Multi-node readiness.** The deliverable targets a single node; PubSub is
  configured but untuned and presence is node-local. Distributed Erlang plus a
  clustered `Phoenix.Presence`, and moving the send rate limiter off a
  single-process ETS table, would be the first steps toward horizontal scale.
- **Delivery and read receipts, typing indicators.** Only an aggregate unread
  count exists today. Per-recipient delivery/read state and typing indicators are
  the natural next messaging primitives, each a small channel event over the
  existing socket.
- **Observability.** Beyond Telemetry and structured logging, request tracing and
  latency histograms per endpoint and channel event would make the stated
  performance targets continuously verifiable rather than checked once locally.

## Development diagnostics

LiveDashboard is available in development only, at
[`/dev/dashboard`](http://localhost:4000/dev/dashboard), for Ecto query
timings, the process tree and memory usage.
