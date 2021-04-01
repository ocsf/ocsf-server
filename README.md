# Splunk Event Schema Server
This is the Splunk Event Schema (SES) server repo.

## Local Usage
This section describes how to build the event schema server.

### Obtaining the Source

Clone the repository:

```bash
git clone https://github.com/splunk/splunk_event_schema.git
```

### Required Build Tools

The event schema server is written in Elixir (https://elixir-lang.org) using the Phoenix web framework (https://phoenixframework.org/).

The Elixir site maintains a great installation page, see https://elixir-lang.org/install.html for help.


### Build the Schema Server

Elixir uses the `mix` build tool, which is included in the Elixir installation package. For more information about `mix`, see https://hexdocs.pm/mix/master/Mix.html and https://hex.pm/docs/usage.

#### Install build tools

```bash
mix local.hex --force && mix local.rebar --force
```

#### Get the dependencies

Change to the schema directory, fetch and compile the dependencies:

```bash
cd server
mix do deps.get, deps.compile
```

#### Compile the source code

```bash
mix compile
```

### Run the Schema Server

Use the Elixir shell command, `iex`, to to start the server:

```bash
PORT=8000 SCHEMA_DIR=schema bin/schema_server start
```

Where:
	PORT					the server port number
	SCHEMA_DIR		the directory containig the Schema JSON files

Now you can visit [`localhost:8000`](http://localhost:8000) from your browser.

## Release the Schema Server

This section describes how to make a release of the event schema server.

### Create a Release

The schema server project uses the [`Elixir Releases`](https://hexdocs.pm/mix/Mix.Tasks.Release.html) to produce an Erlang/OTP release package. To make a release package, run this command:

```bash
MIX_ENV=prod mix release --path dist
```

This command creates the release in the `./dist` directory.

You can use one of the following options to start the Schema server:

```bash
# start a shell, like 'iex -S mix'
> bin/schema_server console

# start in the foreground, like 'mix run --no-halt'
> bin/schema_server foreground

# start in the background, must be stopped with the 'stop' command
> bin/schema_server start
```

If you started the server elsewhere and wish to connect to it:

```bash
# connects a local shell to the running node
> bin/schema_server remote_console

# connects directly to the running node's console
> bin/schema_server attach
```

For a complete listing of commands use:

```bash
bin/schema_server help
```
