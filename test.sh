#!/bin/bash

test() {
  true || return 1
  return 0
}


test || echo "coucou"