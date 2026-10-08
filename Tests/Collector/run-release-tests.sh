#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
for t in \
  contract_architecture.lua metadata_schema_safety.lua collector_core.lua transport_behaviors.lua movement_sampling_transport.lua adaptive_geometry_sampling.lua \
  regression_data_integrity.lua regression_world_sampling.lua regression_resume_stability.lua regression_storage_compaction.lua regression_release_boundaries.lua \
  class_movement_matrix.lua character_identity.lua chunk_integrity.lua corruption_recovery.lua state_combinations.lua \
  recovery_integrity.lua integration_bootstrap.lua coordinate_autocalibration.lua; do
  echo "===== $t ====="
  texlua "$t"
done
