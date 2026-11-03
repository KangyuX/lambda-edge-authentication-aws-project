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
