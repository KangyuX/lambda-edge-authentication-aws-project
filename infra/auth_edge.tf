# Everything the Lambda@Edge function needs at runtime. It reads this once per container,
# so a change here reaches new containers only; warm ones keep the old values until recycled.
resource "aws_ssm_parameter" "auth_config" {
  provider = aws.us_east_1

  name = local.auth_parameter_name
  type = "SecureString"
  value = jsonencode({
    region               = var.region
    userPoolId           = aws_cognito_user_pool.users.id
    userPoolAppId        = aws_cognito_user_pool_client.web.id
    userPoolAppSecret    = aws_cognito_user_pool_client.web.client_secret
    userPoolDomain       = "${aws_cognito_user_pool_domain.auth.domain}.auth.${var.region}.amazoncognito.com"
    cookieExpirationDays = var.session_days
    # /logout clears our cookies, then Cognito's own session, then lands back on the site
    # (which sends the visitor to the sign-in page).
    logoutRedirectUri = "https://${aws_cognito_user_pool_domain.auth.domain}.auth.${var.region}.amazoncognito.com/logout?client_id=${aws_cognito_user_pool_client.web.id}&logout_uri=${urlencode("${local.site_origin}/")}"
    logLevel          = var.auth_log_level
  })
}

locals {
  auth_parameter_name = "/${var.project}/auth-config"
  # A new folder per source change, so files deleted from the source can't linger in the zip.
  auth_build_hash = sha256(join("", concat(
    [for f in ["Dockerfile", ".dockerignore", "index.js", "package.json", "package-lock.json"] : filesha256("${var.auth_source_dir}/${f}")],
    [local.auth_parameter_name],
  )))
  auth_build_dir = abspath("${path.module}/.build/auth-${substr(local.auth_build_hash, 0, 12)}")
}

# Docker builds the function folder (index.js, config.json and node_modules) inside the official
# Lambda Node.js 22 image and copies it out. Lambda@Edge only accepts zip packages, not container
# images, so the folder is zipped below rather than pushed to ECR.
resource "terraform_data" "auth_build" {
  triggers_replace = [local.auth_build_dir]

  provisioner "local-exec" {
    working_dir = var.auth_source_dir
    command     = "docker build --pull --build-arg PARAMETER_NAME=${local.auth_parameter_name} --output ${local.auth_build_dir} ."
  }
}

data "archive_file" "auth" {
  type        = "zip"
  source_dir  = local.auth_build_dir
  output_path = "${path.module}/.build/auth.zip"

  depends_on = [terraform_data.auth_build]
}

data "aws_iam_policy_document" "auth_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "auth" {
  name               = "${var.project}-auth-edge"
  assume_role_policy = data.aws_iam_policy_document.auth_assume.json
}

# Lambda@Edge writes logs in whichever region served the request, so logging can't be scoped to one region.
resource "aws_iam_role_policy_attachment" "auth_logs" {
  role       = aws_iam_role.auth.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "auth_config" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.auth_config.arn]
  }
}

resource "aws_iam_role_policy" "auth_config" {
  name   = "read-auth-config"
  role   = aws_iam_role.auth.id
  policy = data.aws_iam_policy_document.auth_config.json
}

resource "aws_lambda_function" "auth" {
  provider = aws.us_east_1

  function_name    = "${var.project}-auth"
  role             = aws_iam_role.auth.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  filename         = data.archive_file.auth.output_path
  source_code_hash = data.archive_file.auth.output_base64sha256
  memory_size      = 128
  timeout          = 5    # viewer-request maximum
  publish          = true # CloudFront needs a numbered version, not $LATEST
}
