# S3 + CloudFront App with Cognito Sign-In

A static website on AWS that only signed-in users can see. The site files sit in a private S3 bucket, CloudFront serves them over HTTPS, and a Lambda@Edge function checks every request against Amazon Cognito before anything is returned. Everything is built with Terraform in one `terraform apply`.

Every file on the site is behind sign-in, including the CSS, JavaScript and 404 page.

## Architecture

```mermaid
flowchart LR
    U[Browser] -->|HTTPS| CF[CloudFront]
    CF -->|viewer request| L[Lambda@Edge<br/>auth check]
    L -->|no session| C[Cognito<br/>hosted sign-in]
    C -->|"?code=..."| CF
    L -.->|reads settings once| P[SSM Parameter Store]
    CF -->|signed in| S3[(Private S3 bucket)]
```

| Piece | What it does |
| --- | --- |
| **S3** | Holds the static files in `site/`. Public access is blocked, the bucket is encrypted, and only this CloudFront distribution can read it (Origin Access Control). |
| **CloudFront** | Serves the site over HTTPS (HTTP/2 and HTTP/3), caches files, adds AWS's managed security headers, and runs the auth function on every request. |
| **Lambda@Edge** (`auth/`) | Runs before the CloudFront cache on each request, using [cognito-at-edge](https://www.npmjs.com/package/cognito-at-edge). It sends visitors without a valid session to sign in, and lets signed-in visitors through to S3. |
| **Cognito** | User pool with email sign-up, the hosted sign-in page and the OAuth app client. |
| **SSM Parameter Store** | Holds the Cognito settings as an encrypted SecureString. The function reads it once per container. |

### How sign-in works

1. A visitor opens any page. CloudFront runs the auth function first.
2. With no valid session cookie, the function redirects to the Cognito sign-in page.
3. After sign-in, Cognito sends the browser back with a one-time code. The function swaps the code for tokens using the app client secret, which never leaves AWS, stores them in `HttpOnly` cookies and redirects to the page the visitor asked for.
4. Signed-in requests go through to S3. When the ID token expires, the function refreshes it with the refresh token.
5. `/logout` revokes the tokens, clears the cookies, ends the Cognito session and goes back to the sign-in page.

**Why SSM instead of environment variables:** Lambda@Edge doesn't support environment variables. The settings also can't be built into the package, because the Cognito callback URL needs the CloudFront domain, and CloudFront needs the function first.

## Project layout

```
.
├── auth/                 Lambda@Edge function
│   ├── index.js          Request handler
│   ├── package.json      Dependencies (cognito-at-edge)
│   └── Dockerfile        Builds the function package
├── infra/                Terraform
│   ├── hosting.tf        S3 bucket, CloudFront distribution, bucket policy
│   ├── cognito.tf        User pool, hosted sign-in domain, app client
│   ├── auth_edge.tf      Lambda@Edge function, its IAM role, SSM settings, Docker build
│   ├── site_files.tf     Uploads site/ to S3
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
└── site/                 Static website (index.html, styles.css, app.js, 404.html)
```

## Prerequisites

- An AWS account, with credentials set up for the AWS CLI or Terraform (for example `aws configure`)
- [Terraform](https://developer.hashicorp.com/terraform/install) 1.6 or later
- [Docker](https://docs.docker.com/get-docker/), running while you deploy

You don't need Node.js on your machine. Docker installs the function's dependencies.

## Deploy

```bash
git clone <this-repo-url>
cd <repo>/infra
terraform init
terraform apply
```

The first deploy takes about 5 to 10 minutes, mostly while CloudFront rolls out. When it's done, Terraform prints the outputs:

| Output | Meaning |
| --- | --- |
| `site_url` | The site's address (`https://<id>.cloudfront.net`) |
| `user_pool_id` | Cognito user pool, for managing users |
| `bucket_name` | S3 bucket that holds the site |
| `distribution_id` | CloudFront distribution |
| `auth_function_name` / `auth_function_version` | The deployed Lambda@Edge function |

Open `site_url`. You'll be sent to the sign-in page.

### How the function is built

`terraform apply` runs `docker build` on `auth/Dockerfile`. Docker installs the dependencies inside AWS's official Lambda Node.js 22 image, so they match the real runtime, and checks that the handler loads. Terraform then zips the folder it produces (`index.js`, `config.json`, `node_modules/`) and deploys the zip. In the Lambda console you see the handler as written, not a bundled file.

The function is a zip, not a container image, because Lambda@Edge only accepts zip packages. Viewer-request functions must also be under 1 MB zipped, so the Dockerfile strips docs, tests and type definitions from `node_modules`. The package comes out at about 470 KB.

Docker only runs again when a file in `auth/` changes.

## Users

Anyone can create an account with the **Sign up** link on the sign-in page. Cognito emails a verification code, and the account works once the code is entered. Passwords need at least 12 characters, with upper case, lower case and a number.

To create a user yourself (Cognito emails them a temporary password):

```bash
aws cognito-idp admin-create-user \
  --user-pool-id "$(terraform -chdir=infra output -raw user_pool_id)" \
  --username someone@example.com \
  --user-attributes Name=email,Value=someone@example.com Name=email_verified,Value=true
```

Cognito's built-in email sender only sends about 50 emails a day. For more, connect Amazon SES (`email_configuration` on the user pool in `infra/cognito.tf`).

To make the site invite-only, set `allow_admin_create_user_only = true` in `infra/cognito.tf`.

## Configuration

Set variables with `-var name=value` or a `terraform.tfvars` file (ignored by git).

| Variable | Default | Description |
| --- | --- | --- |
| `region` | `us-east-1` | Region for the S3 bucket and Cognito. The Lambda@Edge function and its SSM parameter are always in `us-east-1`, which AWS requires. |
| `project` | `s3-cloudfront-app` | Prefix for every resource name. Change it to deploy a second copy in the same account. |
| `site_dir` | `../site` | Folder uploaded to S3. Must contain `index.html`. |
| `auth_source_dir` | `../auth` | Folder with the function code and its `Dockerfile`. |
| `session_days` | `30` | How long a sign-in lasts (refresh token and cookie lifetime). |
| `auth_log_level` | `warn` | Function log level: `fatal`, `error`, `warn`, `info`, `debug`, `trace` or `silent`. |

## Making changes

- **Site content:** edit files in `site/` and run `terraform apply`. Files are uploaded with `Cache-Control: no-cache`, so changes show up right away without a CloudFront invalidation.
- **Auth function:** edit `auth/index.js`, or add a dependency to `auth/package.json` and `package-lock.json`, then run `terraform apply`. Terraform rebuilds the package with Docker, publishes a new Lambda version and points CloudFront at it. Copying the new version to edge locations takes a few minutes.

## Troubleshooting

- **Where the logs are:** Lambda@Edge writes to CloudWatch in the region of the edge location that handled the request, not only `us-east-1`. Look for the log group `/aws/lambda/us-east-1.<auth_function_name>` in the region closest to you.
- **More detailed logs:** `terraform apply -var auth_log_level=debug`. At `info` and below the logs include tokens, so set it back to `warn` when you're done. Containers that are already running keep the old level until they're replaced.
- **CloudFront returns 503** ("invalid response" or "execution error"): the function threw an error. The stack trace is in the logs above. SSM `AccessDenied` or a missing parameter shows up there too.
- **`redirect_mismatch` on the Cognito page:** the app client's callback URL must be exactly `https://<cloudfront-domain>`, with no trailing slash.
- **`terraform apply` fails at the Docker step:** make sure Docker is running. If `infra/.build/` was deleted, force a rebuild with `terraform apply -replace=terraform_data.auth_build`.

## Security notes

- The bucket isn't public. Only this CloudFront distribution can read it, enforced by a bucket policy scoped to the distribution's ARN.
- The Cognito client secret and token exchange stay on the server side. Tokens are kept in `HttpOnly`, `SameSite=Lax` cookies that page scripts can't read.
- CloudFront only allows `GET`, `HEAD` and `OPTIONS`, and adds AWS's managed security headers (HSTS, `X-Content-Type-Options`, `X-Frame-Options` and others).
- The function's IAM role can only read its own SSM parameter and write logs.
- **Terraform state contains secrets**, including the Cognito client secret. `*.tfstate` is git-ignored, so never commit it. For team use, keep state in an encrypted remote backend such as S3.

## Cost

Everything here is pay-per-use, with no servers running all the time. A low-traffic site usually stays within or close to the AWS Free Tier. The CloudFront distribution uses `PriceClass_100` (edge locations in North America and Europe) to keep costs down. Check current AWS pricing for your usage.

## Tear down

```bash
cd infra
terraform destroy
```

The first `destroy` usually fails on `aws_lambda_function.auth` with a "replicated function" error. AWS takes a while to remove Lambda@Edge copies after CloudFront releases the function. Wait about an hour and run `terraform destroy` again.
