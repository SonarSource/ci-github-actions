'use strict';

const REQUEST_TIMEOUT_MS = 30_000;

function getInput(name, env = process.env) {
  return (env[`INPUT_${name.replaceAll(' ', '_').toUpperCase()}`] || '').trim();
}

function isSaasArtifactory(artifactoryUrl) {
  try {
    const { hostname } = new URL(artifactoryUrl);
    return hostname === 'jfrog.io' || hostname.endsWith('.jfrog.io');
  } catch {
    return false;
  }
}

function probeUrl(artifactoryUrl, probePath) {
  return `${artifactoryUrl.replace(/\/+$/, '')}/${probePath.replace(/^\/+/, '')}`;
}

// Returns the HTTP status, or 0 when the request did not complete.
async function probe(url, accessToken, fetchImpl) {
  try {
    const response = await fetchImpl(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    return response.status;
  } catch {
    return 0;
  }
}

async function waitForTokenFederation({
  artifactoryUrl,
  accessToken,
  probePath,
  timeoutSeconds,
  intervalSeconds,
  fetchImpl = fetch,
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  log = console.log,
}) {
  if (isSaasArtifactory(artifactoryUrl)) {
    log(`Skipping token federation wait for SaaS Artifactory (${artifactoryUrl})`);
    return { skipped: true, attempts: 0 };
  }
  if (!accessToken) {
    throw new Error('No Artifactory access token: set the access-token input or ARTIFACTORY_ACCESS_TOKEN');
  }
  if (!(timeoutSeconds > 0) || !(intervalSeconds > 0)) {
    throw new Error('timeout-seconds and interval-seconds must be positive numbers');
  }

  const url = probeUrl(artifactoryUrl, probePath);
  const maxAttempts = Math.max(1, Math.floor(timeoutSeconds / intervalSeconds));
  log(`Waiting for Artifactory token federation at ${url} (up to ${maxAttempts} attempts, ${intervalSeconds}s apart)`);

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const status = await probe(url, accessToken, fetchImpl);
    if (status === 200) {
      log(`Artifactory token accepted after ${attempt} attempt(s)`);
      return { skipped: false, attempts: attempt };
    }
    if (status !== 401 && status !== 0) {
      throw new Error(`Unexpected response from ${url}: HTTP ${status}`);
    }
    const reason = status === 0 ? 'no response' : 'HTTP 401';
    if (attempt === maxAttempts) {
      throw new Error(`Artifactory token was not accepted by ${url} within ${timeoutSeconds}s (last: ${reason})`);
    }
    log(`Attempt ${attempt}/${maxAttempts}: ${reason}, retrying in ${intervalSeconds}s`);
    await sleep(intervalSeconds * 1000);
  }
  return { skipped: false, attempts: maxAttempts };
}

async function run(env = process.env) {
  try {
    await waitForTokenFederation({
      artifactoryUrl: getInput('artifactory-url', env),
      accessToken: getInput('access-token', env) || (env.ARTIFACTORY_ACCESS_TOKEN || '').trim(),
      probePath: getInput('probe-path', env) || 'api/system/version',
      timeoutSeconds: Number(getInput('timeout-seconds', env) || '300'),
      intervalSeconds: Number(getInput('interval-seconds', env) || '10'),
    });
  } catch (error) {
    console.log(`::error title=Artifactory token federation::${error.message}`);
    process.exitCode = 1;
  }
}

module.exports = { getInput, isSaasArtifactory, probeUrl, waitForTokenFederation, run };

if (require.main === module) {
  run();
}
