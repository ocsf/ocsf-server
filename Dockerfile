ARG elixir_image=elixir:1.17.1-alpine

FROM ${elixir_image} as builder

# prepare build dir
WORKDIR /app

RUN apk --update add openssl

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib

# Compile the release
RUN mix compile
# Generate ssl certificate
RUN openssl req -new -newkey rsa:4096 -days 365 -nodes -sha256 -x509 -subj "/C=US/ST=CA/L=ocsf/O=ocsf.io/CN=ocsf-schema" -keyout priv/cert/selfsigned_key.pem -out priv/cert/selfsigned.pem
# Changes to config/runtime.exs don't require recompiling the code
COPY config/releases.exs  config/runtime.exs

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${elixir_image}

# Set the locale
# RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
EXPOSE 8080
EXPOSE 8443
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"
ENV PORT=8080
ENV SCHEMA_DIR="/app/schema"
ENV SCHEMA_EXTENSION="extensions"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/schema_server ./

USER nobody

CMD ["/app/bin/server"]
