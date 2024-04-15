# JetBrains IDE Services Docker Images

[![JetBrains project](https://jb.gg/badges/official.svg)](https://confluence.jetbrains.com/display/ALL/JetBrains+on+GitHub)

This repository contains official Docker images for JetBrains IDE Services.

# Docker Build Instructions

Follow the steps below to build a Docker image using the provided Dockerfile.

```bash
# check actual version in https://www.jetbrains.com/help/ide-services/get-started.html
IDES_SERVER_VERSION=2024.2.2152

curl -OL https://download.jetbrains.com/ide-services/tbe-launcher-$IDES_SERVER_VERSION.tar
curl -OL https://download.jetbrains.com/ide-services/tbe-launcher-$IDES_SERVER_VERSION.tar.sha256

OUTPUT=$(sha256sum --check tbe-launcher-$IDES_SERVER_VERSION.tar.sha256) || true

if [[ $OUTPUT == *"FAILED"* ]]
then
  echo "Checksum verification failed!"
  exit 1
fi

docker build -t tbe-server:$IDES_SERVER_VERSION .
```