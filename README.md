# Open Cybersecurity Schema Framework Server
This is the Open Cybersecurity Schema Framework (OCSF) server repository.

## Local Usage
This section describes how to build the Event Schema server.

### Obtaining the source code

Clone the Github repository:

```bash
git clone https://github.com/ocsf/ocsf-server.git
```

### Required build tools

The event schema server is written in [Elixir](https://elixir-lang.org) using the [Phoenix](https://phoenixframework.org/) web framework.

The Elixir site maintains a great installation page, see https://elixir-lang.org/install.html for help.


### Building the schema server

Elixir uses the [`mix`](https://hexdocs.pm/mix/Mix.html) build tool, which is included in the Elixir installation package..

#### Install the build tools

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

### Running the schema server

You can use the Elixir's interactive shell, [IEx](https://hexdocs.pm/iex/IEx.html), to start the schema server:

```bash
iex -S mix phx.server
```

The command above start the schema server with the default values (no extensions). See below for details.

### Runtime configuration

The schema server uses a number of environment variables.

```bash
RELEASE_NODE=schema PORT=8000 SCHEMA_DIR=../schema SCHEMA_EXTENSION=extensions iex -S mix phx.server
```

##### Where

| Variable Name    | Description                                               |
| ---------------- | --------------------------------------------------------- |
| RELEASE_NODE     | the Erlang node name                                      |
| PORT             | the server port number, default: `8000`                   |
| SCHEMA_DIR       | the directory containing the schema, default: `../schema` |
| SCHEMA_EXTENSION | the directory containing the schema extensions            |

Now you can visit [`localhost:8000`](http://localhost:8000) from your browser.



## Releasing the schema server

This section describes how to make a release of the event schema server.

### Create a release

The schema server project uses the [`Elixir Releases`](https://hexdocs.pm/mix/Mix.Tasks.Release.html) to produce an Erlang/OTP release package. To make a production release package, run this command:

```bash
MIX_ENV=prod mix release --path dist
```

This command creates the release in the `./dist` directory.

You can use one of the following options to start the Schema server (see the above environment variables):

```bash
# starts the schema server in the foreground
> bin/schema_server start

# starts the schema server with IEx attached, like 'iex -S mix phx.server'
> bin/schema_server start_iex

# starts the schema server in the background, must be stopped with the 'bin/schema_server stop' command
> bin/schema_server daemon
```

For example to start the schema server, with all extensions, from the `dist` folder use:

```bash
SCHEMA_DIR=../../schema SCHEMA_EXTENSION=extensions bin/schema_server start
```

For a complete listing of commands use:

```bash
bin/schema_server
```

### Deploy the release

A release is built on a **host**, a machine which contains Erlang, Elixir, and any other dependencies needed to compile the schema server. A release is then deployed to a **target**, potentially the same machine as the host, but usually a separate target host.

To deploy the schema server, copy the release archive file (`schema_server-<version>.tar.gz`) from the release folder to the target. Extract the release files to disk from the archive. Note, the following must be the same between the **host** and the **target**:

- Target architecture (for example, x86_64 or ARM)
- Target vendor + operating system (for example, Windows, Linux, or Darwin/macOS)
- Target ABI (for example, musl or gnu)
