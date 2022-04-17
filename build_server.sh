#!/bin/bash

# go to the schema server project directory
cd server

# fetch and compile the dependencies
MIX_ENV=prod mix do deps.get, deps.compile, compile

# compile the schema server
MIX_ENV=prod mix compile

# make a release package
MIX_ENV=prod mix release --path dist
