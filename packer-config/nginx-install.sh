#!/bin/bash
sleep 30
sudo apt-get update
sudo apt-get install nginx-light -y
sudo service nginx start
sudo update-rc.d nginx enable
