#!/bin/sh
# Count lookup failures in the app log.
grep -c "fetch_user failed" "${1:-app.log}"
