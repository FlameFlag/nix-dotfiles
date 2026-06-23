#!/bin/sh
# shellcheck shell=sh

exec __NODE_REAL__ --require __HOOK_FILE__ "$@"
