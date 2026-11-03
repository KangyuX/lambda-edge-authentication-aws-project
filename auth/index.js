const fs = require("node:fs");
const path = require("node:path");
const { Authenticator } = require("cognito-at-edge");
const { SSMClient, GetParameterCommand } = require("@aws-sdk/client-ssm");

// Lambda@Edge has no environment variables. Terraform writes config.json next to this file
// with the SSM parameter that holds the Cognito settings; they can't be baked in because the
// app client's callback URL needs the CloudFront domain, which needs this function first.
const { parameterName, parameterRegion } = JSON.parse(
  fs.readFileSync(path.join(__dirname, "config.json"), "utf8"),
);

let authenticatorPromise;

async function loadAuthenticator() {
  const ssm = new SSMClient({ region: parameterRegion });
  const { Parameter } = await ssm.send(
    new GetParameterCommand({ Name: parameterName, WithDecryption: true }),
  );
  const config = JSON.parse(Parameter.Value);

  return new Authenticator({
    region: config.region,
    userPoolId: config.userPoolId,
    userPoolAppId: config.userPoolAppId,
    userPoolAppSecret: config.userPoolAppSecret,
    userPoolDomain: config.userPoolDomain,
    cookieExpirationDays: config.cookieExpirationDays,
    httpOnly: true,
    sameSite: "Lax",
    logoutConfiguration: {
      logoutUri: "/logout",
      logoutRedirectUri: config.logoutRedirectUri,
    },
    logLevel: config.logLevel,
  });
}

// Read SSM once per container; on failure, retry on the next request instead of caching the error.
function getAuthenticator() {
  if (!authenticatorPromise) {
    authenticatorPromise = loadAuthenticator().catch((err) => {
      authenticatorPromise = undefined;
      throw err;
    });
  }
  return authenticatorPromise;
}

exports.handler = async (event) => {
  // cognito-at-edge 1.5.5 crashes on /logout when the request has no cookies (it calls
  // request.headers.cookie.flatMap). Logout requests always get a generated response and
  // never reach S3, so giving them an empty cookie list is safe.
  const { request } = event.Records[0].cf;
  if (request.uri.startsWith("/logout") && !request.headers.cookie) {
    request.headers.cookie = [];
  }

  const authenticator = await getAuthenticator();
  return authenticator.handle(event);
};
