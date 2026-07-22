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

## Development diagnostics

LiveDashboard is available in development only, at
[`/dev/dashboard`](http://localhost:4000/dev/dashboard), for Ecto query
timings, the process tree and memory usage.
