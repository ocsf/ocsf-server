#!/bin/bash

echo Stop the OCSF WEB Server
sudo systemctl stop ocsf_server.service

echo Update the OCSF WEB Server
sudo rm -fr /opt/ocsf/*
cp -r server/dist/* /opt/ocsf
cp -r schema        /opt/ocsf/schema

echo Start the OCSF WEB Server
sudo systemctl start ocsf_schema.service
