FROM elixir:otp-25-alpine as builder

# prepare build dir
WORKDIR /app

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

# Changes to config/runtime.exs don't require recompiling the code
COPY config/releases.exs  config/runtime.exs

COPY rel rel
COPY modules modules
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM elixir:otp-25-alpine

# Set the locale
# RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
EXPOSE 8080
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
