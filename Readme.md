# Toolbox Enterprise Docker Images

[![JetBrains project](https://jb.gg/badges/official.svg)](https://confluence.jetbrains.com/display/ALL/JetBrains+on+GitHub)

This repository contains official Docker images for Toolbox Enterprise.

# Docker Build Instructions

Follow the steps below to build a Docker image using the provided Dockerfile.

```bash
# check actual version in https://www.jetbrains.com/help/toolbox-enterprise/get-started.html
TBE_SERVER_VERSION=1.0.13881.202

curl -O https://download.jetbrains.com/tbe/tbe-launcher-$TBE_SERVER_VERSION.tar
curl -O https://download.jetbrains.com/tbe/tbe-launcher-$TBE_SERVER_VERSION.tar.sha256

OUTPUT=$(sha256sum --check tbe-launcher-$TBE_SERVER_VERSION.tar.sha256) || true

if [[ $OUTPUT == *"FAILED"* ]]
then
  echo "Checksum verification failed!"
  exit 1
fi

docker build -t tbe-server:$TBE_SERVER_VERSION .
```