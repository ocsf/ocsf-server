#!/bin/bash

echo Stop the Schema Web server
sudo systemctl stop splunk_event_schema.service

echo Update the Schema Web server
sudo rm -fr /opt/schema/splunk_event_schema/*
cp -r server/dist/* /opt/schema/splunk_event_schema
cp -r schema        /opt/schema/splunk_event_schema

echo Start the Schema Web server
sudo systemctl start splunk_event_schema.service
