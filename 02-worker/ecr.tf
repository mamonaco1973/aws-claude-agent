# ===============================================================================
# CONTAINER REGISTRY
# ===============================================================================
# apply.sh creates this repository first (targeted apply), pushes the
# image, then applies the rest of the phase.
# ===============================================================================

resource "aws_ecr_repository" "worker" {
  name                 = "claude-agent-worker"
  image_tag_mutability = "MUTABLE"

  # destroy.sh deletes the images first; this is the safety net.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
