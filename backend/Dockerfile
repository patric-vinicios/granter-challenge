ARG ELIXIR_VERSION=1.20.1
ARG ERLANG_VERSION=29.0.2
ARG ALPINE_VERSION=3.22.5

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-alpine-${ALPINE_VERSION} AS build

RUN apk add --no-cache build-base git

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
RUN mix compile

COPY config/runtime.exs config/
COPY rel rel
RUN chmod +x rel/overlays/bin/* && mix release

FROM alpine:${ALPINE_VERSION} AS app

RUN apk add --no-cache libstdc++ libgcc ncurses-libs openssl ca-certificates

RUN addgroup -g 1000 api && adduser -D -H -u 1000 -G api api \
  && mkdir -p /app && chown api:root /app

WORKDIR /app
USER api

ENV PHX_SERVER=true \
    BIND_IP=0.0.0.0 \
    PORT=4000

COPY --from=build --chown=api:root /app/_build/prod/rel/api ./

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:4000/api/health >/dev/null || exit 1

CMD ["/app/bin/server"]
