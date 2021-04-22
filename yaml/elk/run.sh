#!/bin/bash

# 设置memlock无限制
ulimit -l unlimited

exec su elasticsearch /usr/local/bin/docker-entrypoint.sh
