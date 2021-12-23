# Running the Event Schema Server

## Manual Start/Stop

You can manually start the Schema server as a daemon, running in background, using the following command:

```bash
RELEASE_NODE=schema PORT=8000 SCHEMA_DIR=/opt/ses/schema SCHEMA_EXTENSION=extensions bin/schema_server daemon
```

## Using `systemd` to create a service

As `root`, create a new file `/lib/systemd/system/schema_server.service` with the text below:

```bash
[Unit]
Description=Splunk Event Schema Server
After=syslog.target network.target

[Service]
Type=simple
User=ses_user
WorkingDirectory=/opt/ses/schema
Environment="PORT=8000"
Environment="RELEASE_NODE=schema"
Environment="SCHEMA_DIR=/opt/ses/schema/schema"
Environment="SCHEMA_EXTENSION=extensions"
ExecStart=/opt/ses/schema/bin/schema_server start
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

### Notes
  Create a `ses_user` or use any other existing Linux user.
  The Linux user, which is used to run the schema server, must have write access to the *WorkingDirectory* folder.

## Starting the service
To start the `schema_server` service use:

```bash
systemctl start schema_server.service
```

To check if the service is running use:

```bash
systemctl status schema_server.service
```

If you like the schema web server to start at system boot, then run this command:

```bash
systemctl enable schema_server.service
```

