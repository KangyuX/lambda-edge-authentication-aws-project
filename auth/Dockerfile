# Builds the Lambda@Edge package folder: the handler plus its production dependencies,
# installed inside AWS's own Lambda Node.js 22 image so they match the runtime.
# Lambda@Edge can only run zip packages, not container images, so Terraform runs this with
# `docker build --output` to copy the folder out, then zips it.
FROM public.ecr.aws/lambda/nodejs:22 AS build

WORKDIR /var/task
COPY package.json package-lock.json ./
RUN dnf install -y findutils && npm ci --omit=dev

# A viewer-request function must be under 1 MB zipped, so drop what never runs on Lambda:
# docs, type definitions, source maps, tests, and axios's browser and ESM builds
# (on Node, require("axios") loads dist/node/axios.cjs).
RUN find node_modules -type f \( -name '*.md' -o -name '*.d.ts' -o -name '*.d.cts' -o -name '*.d.mts' \
      -o -name '*.map' -o -name '*.yml' -o -name '.eslintrc*' -o -name '.nycrc*' -o -name '*.png' \) -delete \
 && find node_modules -type d \( -name test -o -name tests -o -name docs -o -name benchmarks \
      -o -name examples -o -name .github \) -prune -exec rm -rf {} + \
 && find node_modules/axios/dist -mindepth 1 -maxdepth 1 ! -name node -exec rm -rf {} + \
 && rm -f package-lock.json node_modules/.package-lock.json

COPY index.js ./

# Lambda@Edge has no environment variables, so the handler reads the SSM parameter name from here.
# The last line checks the handler loads (the runtime provides the AWS SDK from /var/runtime).
ARG PARAMETER_NAME
ARG PARAMETER_REGION=us-east-1
RUN test -n "$PARAMETER_NAME" \
 && printf '{"parameterName":"%s","parameterRegion":"%s"}\n' "$PARAMETER_NAME" "$PARAMETER_REGION" > config.json \
 && NODE_PATH=/var/runtime/node_modules node -e 'require("./index.js")'

FROM scratch
COPY --from=build /var/task /
