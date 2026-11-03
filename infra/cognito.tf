# Visitors without an account can sign up from the hosted sign-in page; Cognito emails them
# a code to verify their address before the first sign-in.
resource "aws_cognito_user_pool" "users" {
  name                     = "${var.project}-users"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your ${var.project} verification code"
    email_message        = "Your verification code is {####}"
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

resource "random_id" "auth_domain" {
  byte_length = 4
}

# Hosted sign-in pages at https://<prefix>.auth.<region>.amazoncognito.com
resource "aws_cognito_user_pool_domain" "auth" {
  domain       = "${var.project}-${random_id.auth_domain.hex}"
  user_pool_id = aws_cognito_user_pool.users.id
}

locals {
  site_origin = "https://${aws_cloudfront_distribution.site.domain_name}"
}

# Confidential client: the code-for-token exchange happens inside Lambda@Edge, never in the browser.
resource "aws_cognito_user_pool_client" "web" {
  name            = "${var.project}-web"
  user_pool_id    = aws_cognito_user_pool.users.id
  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  # cognito-at-edge sends redirect_uri=https://<host> (no trailing slash); Cognito matches it exactly.
  callback_urls = [local.site_origin]
  logout_urls   = ["${local.site_origin}/"]

  explicit_auth_flows           = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"

  refresh_token_validity = var.session_days
  token_validity_units {
    refresh_token = "days"
  }
}
