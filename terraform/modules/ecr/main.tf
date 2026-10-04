resource "aws_ecr_repository" "this" {
  name = var.name

  # Images are tagged with the git SHA, so a tag must never be overwritten.
  # That keeps every deployed tag traceable and makes rollback safe.
  image_tag_mutability = "IMMUTABLE"

  # Lets terraform destroy remove the repository even if it still holds images.
  force_delete = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, { Name = var.name })
}

# Keep the newest images only, so storage cost does not grow with every build.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last ${var.max_image_count} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.max_image_count
      }
      action = { type = "expire" }
    }]
  })
}
