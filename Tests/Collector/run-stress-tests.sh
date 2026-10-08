#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
ENGINE="../../Addon/HeroPath/HeroPath.lua"
texlua soak_longrun.lua "$ENGINE"
texlua stress_profiles_2000.lua "$ENGINE"
texlua stress_profiles_10000.lua "$ENGINE"
echo "stress tests passed"
