#!/bin/bash

source "zszefzef"

echo "ok"

test() {
  false || return 1
  return 0
}


test || echo "coucou"