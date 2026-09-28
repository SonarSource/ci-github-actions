'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');

const {
  getInput,
  isSaasArtifactory,
  probeUrl,
  waitForTokenFederation,
  run,
} = require('../token/index.js');

const TOKEN = 'federated-token';

// Answers with the next status of `statuses` (the last one repeats) and records the requests.
function startServer(statuses) {
  const requests = [];
  const server = http.createServer((req, res) => {
    requests.push({ url: req.url, authorization: req.headers.authorization });
    const status = statuses[Math.min(requests.length - 1, statuses.length - 1)];
    res.writeHead(status).end();
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const baseUrl = `http://127.0.0.1:${server.address().port}/artifactory`;
      resolve({ server, requests, baseUrl });
    });
  });
}

function options(baseUrl, overrides = {}) {
  return {
    artifactoryUrl: baseUrl,
    accessToken: TOKEN,
    probePath: 'api/system/version',
    timeoutSeconds: 30,
    intervalSeconds: 10,
    sleep: async () => {},
    log: () => {},
    ...overrides,
  };
}

describe('getInput', () => {
  it('reads the INPUT_ variable GitHub sets for a hyphenated input', () => {
    assert.equal(getInput('artifactory-url', { 'INPUT_ARTIFACTORY-URL': ' https://edge/artifactory ' }), 'https://edge/artifactory');
  });

  it('returns an empty string for a missing input', () => {
    assert.equal(getInput('probe-path', {}), '');
  });
});

describe('isSaasArtifactory', () => {
  it('detects jfrog.io hosts', () => {
    assert.equal(isSaasArtifactory('https://repox.jfrog.io/artifactory'), true);
  });

  it('does not treat the Edge or look-alike hosts as SaaS', () => {
    assert.equal(isSaasArtifactory('https://repox-internal.dev.sonar.build/artifactory'), false);
    assert.equal(isSaasArtifactory('https://jfrog.io.example.com/artifactory'), false);
    assert.equal(isSaasArtifactory('not a url'), false);
  });
});

describe('probeUrl', () => {
  it('joins the base URL and the probe path with a single slash', () => {
    assert.equal(probeUrl('https://edge/artifactory/', '/api/system/version'), 'https://edge/artifactory/api/system/version');
  });
});

describe('waitForTokenFederation', () => {
  it('skips SaaS without sending a request', async () => {
    let called = false;
    const result = await waitForTokenFederation(options('https://repox.jfrog.io/artifactory', {
      fetchImpl: async () => { called = true; },
    }));
    assert.deepEqual(result, { skipped: true, attempts: 0 });
    assert.equal(called, false);
  });

  it('fails without an access token', async () => {
    await assert.rejects(waitForTokenFederation(options('https://edge/artifactory', { accessToken: '' })), /No Artifactory access token/);
  });

  it('rejects a non-positive interval', async () => {
    await assert.rejects(waitForTokenFederation(options('https://edge/artifactory', { intervalSeconds: 0 })), /must be positive/);
  });

  describe('against an Edge', () => {
    let edge;
    after(() => edge?.server.close());

    it('returns once the token is accepted, sending it as a bearer token', async () => {
      edge = await startServer([401, 401, 200]);
      const sleeps = [];
      const result = await waitForTokenFederation(options(edge.baseUrl, { sleep: async (ms) => sleeps.push(ms) }));
      assert.deepEqual(result, { skipped: false, attempts: 3 });
      assert.deepEqual(sleeps, [10_000, 10_000]);
      assert.equal(edge.requests.length, 3);
      assert.equal(edge.requests[0].url, '/artifactory/api/system/version');
      assert.equal(edge.requests[0].authorization, `Bearer ${TOKEN}`);
      edge.server.close();
    });

    it('fails immediately on an unexpected status', async () => {
      edge = await startServer([403]);
      await assert.rejects(waitForTokenFederation(options(edge.baseUrl)), /Unexpected response .*HTTP 403/);
      assert.equal(edge.requests.length, 1);
      edge.server.close();
    });

    it('gives up after timeout-seconds / interval-seconds attempts', async () => {
      edge = await startServer([401]);
      await assert.rejects(waitForTokenFederation(options(edge.baseUrl)), /not accepted .* within 30s \(last: HTTP 401\)/);
      assert.equal(edge.requests.length, 3);
      edge.server.close();
    });
  });

  it('retries when the Edge does not answer', async () => {
    let calls = 0;
    const result = await waitForTokenFederation(options('https://edge/artifactory', {
      fetchImpl: async () => {
        calls++;
        if (calls < 2) throw new TypeError('fetch failed');
        return { status: 200 };
      },
    }));
    assert.deepEqual(result, { skipped: false, attempts: 2 });
  });
});

describe('run', () => {
  let edge;
  let originalLog;
  let output;
  before(async () => {
    edge = await startServer([200]);
    originalLog = console.log;
  });
  after(() => {
    console.log = originalLog;
    edge.server.close();
    process.exitCode = 0;
  });

  function capture() {
    output = [];
    console.log = (line) => output.push(line);
  }

  it('falls back to ARTIFACTORY_ACCESS_TOKEN and succeeds', async () => {
    capture();
    process.exitCode = 0;
    await run({ 'INPUT_ARTIFACTORY-URL': edge.baseUrl, ARTIFACTORY_ACCESS_TOKEN: TOKEN });
    assert.equal(process.exitCode, 0);
    assert.equal(edge.requests.at(-1).authorization, `Bearer ${TOKEN}`);
  });

  it('reports a failure as a workflow error and a non-zero exit code', async () => {
    capture();
    process.exitCode = 0;
    await run({ 'INPUT_ARTIFACTORY-URL': edge.baseUrl });
    assert.equal(process.exitCode, 1);
    assert.match(output.at(-1), /^::error title=Artifactory token federation::No Artifactory access token/);
  });
});
