# Deployment

> ```bash
> # Build and run locally
> docker build -t menegroth .
> docker run -p 8080:8080 menegroth
> curl http://localhost:8080/health
> ```

## Overview

The menegroth API is deployed as a Docker container on AWS App Runner. The CI/CD pipeline automates building, pushing to ECR, updating the App Runner service, and running smoke tests.

## Docker

The `Dockerfile` uses the official `julia:1.12.4` base image:

1. Copies the project files (manifests, source code, scripts)
2. Instantiates the Julia project and precompiles dependencies
3. Runs `scripts/api/sizer_bootstrap.jl` as the entry point

The bootstrap entry point provides fast cold starts: the HTTP server is available immediately for health checks, while StructuralSynthesizer loads in the background.

### Relying on the Docker image (build-time precompile)

The Dockerfile runs a **build-time warmup** before the image is published:

```dockerfile
RUN timeout 1800 julia --project=StructuralSynthesizer -e '\
  using StructuralSynthesizer; \
  Base.invokelatest(register_routes!); \
  @info "Build-time warmup complete"' \
  || { echo "ERROR: build-time warmup timed out or failed"; exit 1; }
```

That step loads `StructuralSynthesizer` and registers routes so Julia precompiles the package and its dependency tree (JuMP, Gurobi, HiGHS, Meshes, etc.) **during `docker build`**. The compiled artifacts are stored in the image under `JULIA_DEPOT_PATH=/app/.julia`.

**At runtime** (e.g. on App Runner), when the container starts it reuses that depot: `using StructuralSynthesizer` loads from the precompiled cache instead of compiling from source. So in theory cold start is only “load from disk” (often under a minute). In practice you may still see longer cold starts because:

- **First-time load of native libs** — Gurobi, HiGHS, Ipopt, etc. are loaded and initialized when the package is first used; that can add tens of seconds.
- **Cache or environment differences** — If the runtime environment differs from build (e.g. different glibc, CPU features, or depot path), Julia may re-precompile some modules, which can take several minutes (as in the “549 seconds” / “197 dependencies successfully precompiled” logs).
- **Scale-to-zero** — When the service has been idle, App Runner may have stopped the container; the next request starts a new instance and pays full cold start.

So “relying on the Docker image” means: the image is built with a full warmup so that **typical** cold start is much shorter than a clean machine. If the runtime matches the build environment well, startup is often on the order of 1–2 minutes; if not, the first request can still trigger a long precompile. The Grasshopper client waits up to 1 hour for “API ready” and offers a **Cancel** option so the user can stop waiting if needed.

### Storing the environment so startup isn’t necessary

The environment (packages + precompiled code) is already stored in the image under `/app/.julia`. Every new container gets that copy. There is no separate “cloud store” of the environment: App Runner doesn’t support persistent volumes, so you can’t persist a depot between container restarts. You can still reduce or hide cold start in these ways:

1. **Keep one instance warm**  
   In App Runner, set **Minimum capacity** to **1**. One container stays running; its in-memory state (loaded packages) stays hot. Cold start only happens when that instance is replaced (e.g. after a deploy). Trade-off: you pay for that instance even when idle.

2. **Match build and run environment**  
   Build the image for the same architecture and OS as the cloud (e.g. `linux/amd64`). In GitHub Actions, the default runner is amd64; App Runner is typically amd64. If they match, Julia is less likely to invalidate the precompiled cache at runtime. Ensure `JULIA_DEPOT_PATH` is the same at build and run (`/app/.julia` in the Dockerfile).

3. **Custom sysimage (PackageCompiler)**  
   You can “store” the environment as a single native image (a `.so` sysimage) that Julia loads at startup instead of loading many `.ji` files. That makes startup faster and more predictable (often tens of seconds instead of minutes).  
   - Add a build step that uses [PackageCompiler.jl](https://julialang.github.io/PackageCompiler.jl/stable/) to create a custom sysimage that includes `StructuralSynthesizer` and the code paths used by the API (e.g. `register_routes!`, design pipeline).  
   - Save the sysimage in the image (e.g. `/app/sys.so`) and run with `julia -J /app/sys.so --project=StructuralSynthesizer scripts/api/sizer_bootstrap.jl`.  
   This requires a one-time setup (script or extra Docker stage) and longer image build times, but cold start in the cloud becomes much shorter and more consistent. The “environment” is then literally one file (the sysimage) plus the project.

4. **Persistent volume (other services only)**  
   If you move off App Runner to something that supports volumes (e.g. ECS with EFS, or an EC2 instance with an EBS volume), you could put `JULIA_DEPOT_PATH` on that volume. The first run would populate it; later runs (or new containers mounting the same volume) would reuse it. App Runner does not support this.

**Summary:** The image already stores the environment; cold start is “load that environment into a new container.” To avoid waiting on that, keep one instance warm (min capacity 1) and/or add a custom sysimage so loading is faster.

## AWS App Runner

The deployment uses AWS App Runner for managed container hosting:

- **Automatic scaling** — scales from 0 to N instances based on request volume
- **Health checks** — `GET /health` used for liveness probing
- **HTTPS termination** — handled by App Runner's load balancer

## CI Pipeline

**Source:** `.github/workflows/deploy-api.yml`

The GitHub Actions workflow triggers on pushes to `main` and `workflow_dispatch`:

| Step | Description |
|:-----|:------------|
| Checkout | Clone repository |
| AWS OIDC Auth | Authenticate via OpenID Connect (no long-lived credentials) |
| ECR Login | Authenticate to Amazon ECR |
| Docker Build & Push | Build image and push to ECR repository |
| App Runner Update | Update the App Runner service with the new image |
| Smoke Test (health) | Poll `GET /health` until `200 OK` (up to 24 attempts, 10s interval) |
| Smoke Test (schema) | Verify `GET /schema` returns valid response |

### Required Secrets

| Secret | Description |
|:-------|:------------|
| `APP_RUNNER_SERVICE_ARN` | ARN of the App Runner service |
| `ECR_REPOSITORY` | ECR repository name |
| `APP_URL` | Public URL of the deployed service (e.g. `https://xxx.us-east-1.awsapprunner.com`). Use this as the **Server URL** in the Grasshopper SizerRun component. |

## Bootstrap vs Service Mode

| Aspect | Bootstrap | Service |
|:-------|:----------|:--------|
| Startup time | ~5s (health available), ~60s (full) | ~60s (full) |
| Entry point | `sizer_bootstrap.jl` | `sizer_service.jl` |
| Cold start | Fast — serves `/health` immediately | Slow — blocks until loaded |
| Use case | Production (App Runner health checks) | Development |

Bootstrap mode is preferred for production because App Runner requires a health check response within a timeout. The bootstrap server responds to `/health` immediately and returns `{"status": "warming"}` for `/status` until the full package is loaded.

## Environment Variables

| Variable | Description | Default |
|:---------|:------------|:--------|
| `PORT` / `SIZER_PORT` | HTTP listen port | `8080` |
| `SIZER_HOST` | Bind address | `0.0.0.0` |
| `SS_ENABLE_VISUALIZATION` | Include visualization data in API output | `false` |
| `SS_ENABLE_HEAVY_PRECOMPILE_WORKLOAD` | Run a precompilation workload on startup to warm the JIT | `false` |

### Gurobi license (optional)

To use Gurobi on the server instead of HiGHS, provide a license in one of these ways:

**Option A — Web License Service (WLS)**  
Set these environment variables in the App Runner service (e.g. in AWS Console → App Runner → your service → Configuration → Environment variables). Prefer storing values in AWS Secrets Manager and referencing them in App Runner.

| Variable | Description |
|:---------|:------------|
| `GRB_WLSACCESSID` | WLS access ID from [Gurobi Web License Manager](https://license.gurobi.com/) → API Keys |
| `GRB_WLSSECRET` | WLS secret from the same API key |
| `GRB_LICENSEID` | License ID (numeric) |

Gurobi will use these at runtime; no file is needed.

**Option B — License file path**  
If you have a `gurobi.lic` file in the image (e.g. baked in at build time via a Docker build secret):

| Variable | Description |
|:---------|:------------|
| `GRB_LICENSE_FILE` | Path to the license file, e.g. `/opt/gurobi/gurobi.lic` |

**Option C — License content via env var**  
If the container uses the optional entrypoint (see below), you can set:

| Variable | Description |
|:---------|:------------|
| `GRB_LICENSE_CONTENTS` | Full contents of `gurobi.lic` (single line or newlines). Written to a file at startup; `GRB_LICENSE_FILE` is set automatically. |

Store the value in AWS Secrets Manager and inject it as an environment variable in App Runner so the license is not in the image.

### Performance Tuning

- **`SS_ENABLE_HEAVY_PRECOMPILE_WORKLOAD`** — runs a representative design on startup to compile all code paths. Increases startup time by ~30s but eliminates first-request latency.
- **`SS_ENABLE_VISUALIZATION`** — visualization data (node positions, frame elements, deflected meshes) adds significant serialization overhead. Disable for API-only use cases.

## Health Check Configuration

App Runner health check settings:

| Setting | Value |
|:--------|:------|
| Path | `/health` |
| Protocol | HTTP |
| Interval | 10s |
| Timeout | 5s |
| Healthy threshold | 1 |
| Unhealthy threshold | 5 |

## Limitations & Future Work

- No horizontal scaling coordination; each instance is independent with its own in-memory cache.
- Blue/green deployment with traffic shifting is handled by App Runner but not explicitly configured.
- Container image size (~2 GB due to Julia + dependencies) could be reduced with a multi-stage build.
