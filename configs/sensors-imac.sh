#!/bin/bash
set -euo pipefail

sensors 2>/dev/null | grep -v "amdgpu" || true
