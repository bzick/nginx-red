#!/bin/bash
INSTALL_DIR=/tmp
curl -silent --location https://github.com/Orange-OpenSource/hurl/releases/download/2.0.1/hurl-2.0.1-x86_64-linux.tar.gz | tar xvz -C $INSTALL_DIR
mv $INSTALL_DIR/hurl-2.0.1 $INSTALL_DIR/hurl