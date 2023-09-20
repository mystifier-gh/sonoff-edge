#!/bin/bash
URL="https://github.com/SmartThingsCommunity/smartthings-cli/releases/download/%40smartthings%2Fcli%401.6.0/smartthings-linux-x64.tar.gz"
if [ -f "tools/smartthings" ]; then
    echo "smartthings exists"
else
    wget $URL -O - | tar -xz -C tools
fi
pushd hub
poetry install
popd