#!/bin/bash
# Build time only: the global tools, each at the newest version that supports this image's Node major.
#   TypeScript stays on 5.x: 7.x is the native (Go) compiler without the JavaScript API that ts-node uses.
set -euo pipefail

major="$(node -p 'process.versions.node.split(".")[0]')"

if [ "${major}" -ge 14 ]; then typescript='typescript@5'; else typescript='typescript@~5.0.4'; fi
if [ "${major}" -ge 22 ]; then pnpm='pnpm@11'
elif [ "${major}" -ge 18 ]; then pnpm='pnpm@10'
elif [ "${major}" -ge 16 ]; then pnpm='pnpm@8'
elif [ "${major}" -ge 14 ]; then pnpm='pnpm@7'
else pnpm='pnpm@6'
fi

packages=(yarn@1 "${pnpm}" "${typescript}" ts-node@10 @types/node)
# tsx 4 needs Node 18; tsx 3 runs on 16 and 17; older Node versions use ts-node only
if [ "${major}" -ge 18 ]; then packages+=(tsx@4); elif [ "${major}" -ge 16 ]; then packages+=(tsx@3); fi

echo "Node ${major}: npm install -g ${packages[*]}"
npm install -g --no-audit --no-fund --no-update-notifier "${packages[@]}"
npm cache clean --force >/dev/null 2>&1 || true
