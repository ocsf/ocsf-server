#!/bin/bash

cd /ocsf-server
if [[ ! -d ./_build ]]; then
    rm -Rf .mix/
    rm -Rf deps/
    mix local.hex --force
    mix local.rebar --force
    mix do deps.get, deps.compile
    mix compile
fi

exec "$@"