# Optional community engines

Signal Sieve keeps its deterministic analyzers available without a server,
account, model, or third-party checkout. Community engines are an optional
second layer for users who deliberately want independently maintained tooling.
They are not downloaded, started, updated, or trusted by the app.

The first adapter targets
[`guillaumemeyer/watermarks-remover`](https://github.com/guillaumemeyer/watermarks-remover),
whose core service publishes a JSON/base64 HTTP contract. Signal Sieve uses the
documented `GET /health`, `GET /capabilities`, `POST /inspect`, and `POST /clean`
routes. It does not invent a provider verdict, and it does not call the
project's optional heavyweight harnesses implicitly.

## Why an adapter instead of vendoring the project

- The community can improve the engine and its format-specific tools without a
  Signal Sieve release.
- Signal Sieve remains useful when the engine is missing, stopped, or broken.
- Each project retains its own license, release process, tests, and security
  boundary.
- The adapter can reject an incompatible response and reanalyze cleaned text
  with Signal Sieve's native detectors before offering it as Result.

This is composition, not code ownership: the external project is neither
forked nor copied into the Signal Sieve source tree.

## Start the compatible service

Review the upstream source and release notes first. The shortest upstream
installation uses Python 3.10 or newer:

```sh
git clone https://github.com/guillaumemeyer/watermarks-remover.git
cd watermarks-remover
python3 service/scripts/server.py --host 127.0.0.1 --port 8765
```

Alternatively, use its published core container:

```sh
docker pull ghcr.io/guillaumemeyer/watermarks-remover:latest
docker run --rm \
  -p 127.0.0.1:8765:8765 \
  --read-only \
  --tmpfs /tmp \
  ghcr.io/guillaumemeyer/watermarks-remover:latest
```

`latest` follows community updates. For a repeatable or audited installation,
replace it with a reviewed release tag and update deliberately. Signal Sieve
does not run `git pull`, `docker pull`, package installation, or a shell command
on the user's behalf.

In Signal Sieve, paste text, choose **Community Engines**, confirm that the
local service is ready, and then choose **Inspect with Engine** or **Create
Community Clean Copy**. The latter does not replace Input or the clipboard. It
shows the engine report, performs a native residual-risk analysis, and requires
**Use as Result**.

Developers can verify the complete adapter against a running compatible service
with a synthetic hidden-Unicode fixture:

```sh
./community-engine-smoke-test.sh
```

The smoke test exercises health, capabilities, inspect, clean, and Signal
Sieve's native residual-risk analysis. It fails closed and never uses clipboard
contents.

### Manual GitHub compatibility run

Maintainers can open **Actions → Community Engine Compatibility → Run
workflow** to verify a reviewed upstream commit without making it a dependency
of every push or release. The input must be the full lowercase commit SHA from
`guillaumemeyer/watermarks-remover`; the checked-out revision is verified before
any upstream code runs.

The manual job runs the upstream test suite, starts its stdlib service only on
`127.0.0.1:8765`, and runs Signal Sieve's health, capabilities, inspect, clean,
adversarial-Unicode, and residual-risk checks. It uploads the bounded service
log for seven days and receives only read access to this repository.

## Privacy and trust boundary

- The endpoint is compiled as the numeric loopback address
  `http://127.0.0.1:8765`; arbitrary hosts and redirects are not accepted.
- Opening the panel checks `/health` but sends no copied text. Text leaves the
  app only after an explicit inspect or clean action.
- Requests are limited to 1 MiB, responses to 2 MiB, and operations to a
  bounded timeout. Request files are temporary and owner-readable only.
- The fixed `/usr/bin/curl` client is launched directly, without a shell, with
  proxy environment variables removed and `--noproxy '*'`.
- A local service still receives the selected text and executes with the
  authority granted to its process. Loopback is a routing boundary, not a
  sandbox. Review the external source, image digest, dependencies, and license.
- The first adapter supports the service's default unauthenticated loopback
  configuration. A deployment requiring `WATERMARKS_SERVER_API_KEY` is not yet
  accepted by this UI.

## Result semantics

An external report proves only what its named detector and configuration can
support. A result is not proof of authorship, AI generation, provider identity,
or malicious intent. Provider-keyed and learned watermarks remain untestable
unless the matching detector, keys or validation material, tokenizer, and
calibrated configuration are actually present.

The current adapter sends `clipboard.txt`; image and container operations stay
in Signal Sieve's File Inspector and Pixel Lab. Future adapters must use a
versioned capability contract, bounded inputs and outputs, explicit execution,
and native post-analysis before they can be enabled.
