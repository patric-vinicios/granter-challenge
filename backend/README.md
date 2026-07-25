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

This builds `Dockerfile.dev`, the development image, which compiles from source
and runs `mix phx.server`. The plain `Dockerfile` is the release image a deploy
uses — see [Deploying](#deploying).

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

mix setup
mix phx.server
```

In development `config/runtime.exs` loads `.env` itself, so nothing needs
exporting; a variable already present in the shell overrides the file. The file
is not optional: startup aborts naming any missing secret, in every environment
except `test`.

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
unused-dependency check, formatter, Credo, coverage, duplication check, a
Sobelow security scan and a dependency audit:

```sh
mix precommit
```

`mix ci` is the same gate for a machine that must not rewrite files — see
[Continuous integration](#continuous-integration).

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
a dependency or Erlang/Elixir upgrade pays the build again. There is no ignore
file: the run is expected to report zero errors and zero skips.

## Environment variables

`.env.example` carries a working local default for everything a development run
reads. `.env.prod.example` covers a deployment instead: the same secrets with
blank values, plus `PHX_HOST` and the database credentials, and it is the file
[Deploying](#deploying) uses. The remaining variables below are optional knobs
that neither file sets.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `DATABASE_URL` | in `prod` | credentials in `config/dev.exs` | Database connection. Set by the `api` container to reach postgres by service name. |
| `SECRET_KEY_BASE` | yes, outside `test` | — | Signs and encrypts Phoenix payloads. Generate with `mix phx.gen.secret`. |
| `JWT_SECRET` | yes, outside `test` | — | Signs the bearer tokens issued by the authentication endpoints. Generate with `mix phx.gen.secret`. |
| `CORS_ORIGINS` | in `prod` | `http://localhost:5173,http://localhost:3000` | Comma-separated browser origins allowed to call the API and to open a socket. |
| `PHX_HOST` | in `prod` | — | Public hostname used for generated URLs. |
| `PORT` | no | `4000` | Port the endpoint listens on. |
| `BIND_IP` | no | `127.0.0.1` | Interface to bind. The dev Compose file and the release image both set `0.0.0.0`, so the published port is reachable. |
| `PHX_SERVER` | no | — | Starts the endpoint when the release is booted by something other than `mix phx.server`. Set by the release image. |
| `DATABASE_SSL` | no | off | `true` connects to the database over TLS, verifying the chain against the OS trust store. Most managed instances need it. |
| `POOL_SIZE` | no | `10` | Ecto connections per instance. Keep the total under the database's own limit. |
| `ECTO_IPV6` | no | off | `true` adds `:inet6` to the database socket options. |
| `TRUST_PROXY_HEADERS` | no | off | `true` takes the client address from `x-forwarded-for`. Set it **only** behind a proxy that overwrites that header — see [Logging](#logging). |

`DATABASE_URL`, `CORS_ORIGINS` and `PHX_HOST` are required in `prod` only, and
`config/runtime.exs` enforces it: the boot aborts naming whichever is missing,
rather than falling back to a localhost default that would leave the deployed
frontend rejected by CORS with nothing in the log to explain it.

## Logging

Phoenix logs every request and Ecto every query, so `ApiWeb.EventLog` holds only
what those two cannot express: who authenticated, which credential was refused,
when a limiter engaged, and when the database stopped answering. Routing them
through one module is what keeps the levels consistent and the field names
stable enough to alert on.

Every line is `event=<name>` followed by `key=value` pairs, so a log search needs
no parser:

```
02:08:50.563 [info] event=boot env=prod cors_origins=https://app.example.com
02:10:08.789 request_id=GMVmZFazFKLk [info] event=account_registered user_id=b4afda65… username=ciuser
02:11:14.002 request_id=GMVmaB0sJPQ2 [warning] event=login_throttled username=demo ip=203.0.113.9 retry_after_s=37
```

| Event | Level | Emitted when |
|---|---|---|
| `boot` | info | The endpoint came up. Names the environment and the effective CORS allowlist — the deploy setting most likely to be wrong, and the one whose failure leaves nothing else in the log. |
| `account_registered` | info | An account was created. |
| `login_succeeded` | info | A password was accepted. |
| `login_failed` | info | A password was rejected. Deliberately not a warning: one wrong password is ordinary user error, and warning on it trains everyone to ignore warnings. |
| `login_throttled` | **warning** | The per-IP or per-username ceiling engaged, which means a burst of failures preceded it. This is the attack signal. |
| `logged_out` | info | A token was revoked by its owner. |
| `token_rejected` | info | A 401 from the pipeline, with the reason that produced it — expired, revoked or malformed, which the status alone does not distinguish. |
| `socket_rejected` | **warning** | A refused WebSocket handshake. A warning unlike a refused HTTP token, because a client reaching the socket has already authenticated over HTTP. |
| `message_rate_limited` | **warning** | The per-user send ceiling engaged on a channel. |
| `database_unavailable` | **error** | The health probe's `SELECT 1` failed. The 503 body stays generic; the reason is logged, which is the only place it can be read without disclosing internals. |

Three properties hold by construction, and are covered by
`test/api_web/logging_test.exs`:

- **No credential is ever logged.** Every `EventLog` function takes only ids,
  usernames, addresses and reasons — there is no parameter a token, password or
  hash could arrive through. The tests assert the password and the issued token
  are absent from the log of a real login.
- **Lines are correlatable.** `request_id` comes from `Plug.RequestId`, and
  `ApiWeb.Plugs.AssignCurrentUser` puts `user_id` into `Logger.metadata/1`, so
  every line a request emits after authentication carries both. The socket does
  the same for its process.
- **The health probe does not drown the log.** An orchestrator and a load
  balancer hit `/api/health` every few seconds. `ApiWeb.Endpoint.log_level/1`
  demotes just that route to `:debug`, so production (`:info`) never sees it
  while `mix phx.server` still does.

**Behind a proxy, set `TRUST_PROXY_HEADERS=true`.** Otherwise every request
appears to come from the proxy's address, and two things quietly break: the
per-IP login ceiling becomes one shared bucket for the whole internet, and every
`login_failed` line names the proxy instead of the client. It is off by default
because the header is only trustworthy when a proxy that *overwrites* it sits in
front of every request — reaching the endpoint directly, a client could forge it
and hand itself a private throttle bucket per address.

## Continuous integration

One workflow per check, in [`.github/workflows/`](../.github/workflows/), each
running on every push to `main` and every pull request that touches `backend/`.
Splitting them means the failing check is the one named red, with no log to read
to find out which step broke.

| Workflow | What it proves |
|---|---|
| `backend-compile.yml` | `mix compile --warnings-as-errors` |
| `backend-format.yml` | `mix format --check-formatted` |
| `backend-credo.yml` | `mix credo --strict` |
| `backend-test.yml` | `mix coveralls` against a real Postgres 16, on the port `config/test.exs` already expects, with the 80% coverage floor from `coveralls.json` |
| `backend-duplication.yml` | `mix ex_dna` |
| `backend-security.yml` | `mix sobelow --exit --skip` |
| `backend-deps.yml` | No unused lock entry, no vulnerable dependency, no retired package |
| `backend-dialyzer.yml` | Zero type errors, with the PLT cached on `mix.lock` so only a dependency or toolchain move pays the rebuild |
| `backend-release-image.yml` | `docker-compose.prod.yml` builds, migrations run at boot, the container reports healthy, `/api/health` answers, and a registration round trip succeeds — which exercises the argon2 NIF, the part of a release image most likely to break on a missing runtime library |

Together they are `mix precommit` with two substitutions: formatting is verified
rather than applied, and an unused lock entry fails rather than being pruned.
`mix ci` runs that same set locally in one shot.

## Deploying

The release image is a two-stage build: a builder that compiles an OTP release,
and an Alpine runtime that carries neither compiler nor sources.

```sh
cp .env.prod.example .env.prod   # fill in every value, secrets included
docker compose --env-file .env.prod -f docker-compose.prod.yml up --build -d

curl localhost:4000/api/health
```

`--env-file` is required: a service-level `env_file` reaches the container but
not Compose's own `${...}` interpolation. The `api` container publishes on
loopback only, because `config/prod.exs` sets `force_ssl` — TLS is expected to
terminate at a reverse proxy in front of it, which forwards `x-forwarded-proto`.
`/api/health` is excluded from that redirect, by path and by host, so a probe
arriving over plain HTTP is answered rather than bounced. Set
`TRUST_PROXY_HEADERS=true` once that proxy is in place, for the reason
[Logging](#logging) gives.

On a platform that provides its own Postgres, drop the `postgres` service and
point `DATABASE_URL` at the managed instance with `DATABASE_SSL=true`. On a PaaS
that builds the Dockerfile itself, set the same variable names as platform
config and skip `.env.prod` entirely — `config/runtime.exs` only auto-loads a
`.env` in `dev`.

**Migrations run at boot.** `CMD` is `bin/server`, which runs `bin/migrate` and
only then starts the endpoint, so a failed migration exits non-zero instead of
serving requests against an unexpected schema. Both scripts live in
`rel/overlays/bin/` and call `Api.Release`, because `mix ecto.migrate` does not
exist inside a release. A platform with a dedicated release phase can call
`bin/migrate` there instead. Rolling back is manual, by timestamp, and the
timestamp given is itself reverted along with everything applied after it:

```sh
docker compose --env-file .env.prod -f docker-compose.prod.yml exec api \
  bin/api eval 'Api.Release.rollback(Api.Repo, 20260724133326)'
```

`--env-file` is needed here too, for the same interpolation reason.

**Scale vertically, for now.** `Phoenix.PubSub` runs on the local node — there is
no `dns_cluster` or `libcluster` in the dependency list — so a second instance
would fan a message out only to the sockets connected to its own node, and
`ApiWeb.Presence` would track only its own. Rate limiting and the revoked-token
set are per-node ETS for the same reason. One instance is therefore the supported
topology; a bigger box is the scaling path until clustering (or a PubSub adapter
backed by Postgres or Redis) is added deliberately.

**A deployed instance starts empty.** `Api.Seeds` refuses to run when the
compiled environment is `prod`, so the demo accounts listed above exist only in
development — register through `POST /api/auth/register` instead.

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

## Development diagnostics

LiveDashboard is available in development only, at
[`/dev/dashboard`](http://localhost:4000/dev/dashboard), for Ecto query
timings, the process tree and memory usage.
