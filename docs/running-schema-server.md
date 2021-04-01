# Running the Event Schema Server

## Manual Start/Stop

You can manually start the Schema erver as a daemon, running in background, using the following command:

```bash
PORT=8000 RELEASE_NODE=schema SCHEMA_DIR=/opt/ses/schema bin/schema_server daemon
```

## Using `systemd`

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
ExecStart=/opt/ses/schema/bin/schema_server start
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

To start the schema_server service:

```bash
systemctl start schema_server.service
```

If you like the schema web server to start at system boot, then run this command:

```bash
systemctl enable schema_server.service
```

