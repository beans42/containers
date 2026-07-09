#!/bin/sh
cp -a /src/. /app && bun install && exec bun run start
