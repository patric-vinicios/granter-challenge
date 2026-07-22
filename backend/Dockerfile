ARG ELIXIR_VERSION=1.20.1
ARG ERLANG_VERSION=29.0.2
ARG ALPINE_VERSION=3.22.5

# Separate stage so editing source does not invalidate the dependency layer.
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-alpine-${ALPINE_VERSION} AS deps

RUN apk add --no-cache build-base git

WORKDIR /app

ENV MIX_ENV=dev

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get
COPY config config
RUN mix deps.compile

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-alpine-${ALPINE_VERSION} AS app

# postgresql-client is for inspecting the database when the api will not start.
RUN apk add --no-cache build-base git postgresql-client

WORKDIR /app

# Dev rather than a release: the demo seeds refuse to run under MIX_ENV=prod.
ENV MIX_ENV=dev

RUN mix local.hex --force && mix local.rebar --force

COPY --from=deps /app/deps deps
COPY --from=deps /app/_build _build
COPY --from=deps /root/.mix /root/.mix

COPY . .

RUN mix compile

EXPOSE 4000

CMD ["mix", "phx.server"]
