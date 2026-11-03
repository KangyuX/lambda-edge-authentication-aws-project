variable "region" {
  description = "AWS region for the S3 bucket."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "s3-cloudfront-app"
}

variable "site_dir" {
  description = "Directory holding the static files to upload."
  type        = string
  default     = "../site"

  validation {
    condition     = fileexists("${var.site_dir}/index.html")
    error_message = "No index.html in site_dir."
  }
}

variable "auth_source_dir" {
  description = "Directory holding the Lambda@Edge handler and its Dockerfile. Terraform runs `docker build` there."
  type        = string
  default     = "../auth"

  validation {
    condition     = fileexists("${var.auth_source_dir}/Dockerfile")
    error_message = "No Dockerfile in auth_source_dir."
  }
}

variable "auth_log_level" {
  description = "cognito-at-edge log level: fatal, error, warn, info, debug, trace or silent. info and below write tokens to CloudWatch, so only lower it while debugging."
  type        = string
  default     = "warn"

  validation {
    condition     = contains(["fatal", "error", "warn", "info", "debug", "trace", "silent"], var.auth_log_level)
    error_message = "auth_log_level must be one of fatal, error, warn, info, debug, trace, silent."
  }
}

variable "session_days" {
  description = "How long a sign-in lasts: the refresh token validity and the cookie lifetime."
  type        = number
  default     = 30
}
