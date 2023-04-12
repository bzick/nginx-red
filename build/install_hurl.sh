#!/bin/bash

set -exo pipefail

wget -q -O - https://github.com/Orange-OpenSource/hurl/releases/download/2.0.1/hurl-2.0.1-x86_64-linux.tar.gz | tar xvz -C /tmp
mv /tmp/hurl-2.0.1 /tmp/hurl