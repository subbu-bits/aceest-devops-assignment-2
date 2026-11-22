# ACEest Fitness & Gym - DevOps CI/CD Pipeline (Assignment 2)

A Flask web application for gym and fitness management, delivered through a fully
automated CI/CD pipeline:

**Git/GitHub → Jenkins → Pytest → SonarQube → Docker → Docker Hub → Kubernetes (Minikube)**

This continues [Assignment 1](https://github.com/subbu-bits/aceest-devops-assignment-1)
(Flask port of the Tkinter app, Pytest, Docker, Jenkins CI, GitHub Actions) and adds
SonarQube, Docker Hub, versioned releases, Kubernetes and five deployment strategies
with automatic rollback.

---

## 1. Architecture

```
 Developer ──git push──▶ GitHub ──Poll SCM (5 min)──▶ Jenkins (college VM)
                                                        │
   Checkout → Install → Lint → Unit Tests + Coverage ───┤
   → SonarQube Analysis → Quality Gate ─────────────────┤ fail = stop
   → Docker Build → Pytest inside container → Artifacts ┤
   → Push to Docker Hub (<user>/aceest-fitness:<version>)
   → Deploy to Kubernetes (chosen strategy) → Verify ───┴── fail = automatic rollback
                                                        │
                    Minikube cluster: one namespace per strategy
     rolling :30081 · blue-green :30082 (preview :30092) · canary :30083
     A/B testing :30084 · shadow :30085
```

GitHub Actions (`.github/workflows/main.yml`, from Assignment 1) still runs lint, Docker
build and tests on every push and pull request.

## 2. Application versions

The ten Tkinter versions (1.0 → 3.2.4) are mapped to five Flask releases. One code base,
with each feature group switched on from the release that introduced it
(`FEATURE_RELEASES` in `app.py`). The version comes from the `VERSION` file
(or the `APP_VERSION` environment variable).

| Version | Adds | Tkinter versions |
|---|---|---|
| 1.0 | Fitness programs (`/programs`) | Aceestver-1.0 |
| 1.1 | Calories, client profiles (`/calories`, `/clients`) | 1.1, 1.1.2 |
| 2.0.1 | Weekly progress tracking (SQLite) | 2.0.1, 2.1.2, 2.2.1 |
| 2.2.4 | BMI, workout logging | 2.2.4, 3.0.1 |
| 3.2.4 | Program generator | 3.1.2, 3.2.4 |

`GET /version` returns the version, its features and the pod's hostname, which shows
which pod (blue/green, stable/canary, A/B) answered a request.

Every release is a git tag (`v1.0` … `v3.2.4`) and a Docker Hub image tag
(`<user>/aceest-fitness:1.0` … `:3.2.4`, plus `:<version>-b<build>` and `:latest`).

## 3. Endpoints

| Feature | Endpoint | Since |
|---|---|---|
| Health check, version info | `GET /health`, `GET /version` | 1.0 |
| Fitness programs | `GET /programs`, `GET /programs/<code>` | 1.0 |
| Daily calorie estimate | `POST /calories` | 1.1 |
| Clients (create, list, view, delete) | `POST/GET /clients`, `GET/DELETE /clients/<name>` | 1.1 |
| Weekly adherence | `POST/GET /clients/<name>/progress` | 2.0.1 |
| BMI | `POST /bmi` | 2.2.4 |
| Workout logging | `POST/GET /clients/<name>/workouts` | 2.2.4 |
| Program generator | `POST /clients/<name>/generate-program` | 3.2.4 |

## 4. Project structure

```
├── app.py                     # Flask application (all versions, feature registry)
├── VERSION                    # Current release version
├── requirements.txt
├── tests/                     # Pytest: logic, API, per-version behaviour (82 tests)
├── Dockerfile                 # python:3.12-slim, non-root, gunicorn, healthcheck
├── Jenkinsfile                # Full CI/CD pipeline
├── sonar-project.properties   # SonarQube settings
├── k8s/                       # Kubernetes manifests
│   ├── namespaces.yaml
│   ├── rolling/  blue-green/  canary/  ab-testing/  shadow/
├── scripts/
│   ├── deploy.sh              # Deploy with a strategy (auto rollback on failure)
│   ├── rollback.sh            # Return a strategy to its stable version
│   ├── promote.sh             # Make the canary / B variant / shadow the new stable
│   ├── verify.sh, smoke_test.sh
│   ├── endpoints.sh           # Show every endpoint and which versions answer
│   ├── release_all_versions.sh
│   └── sonar_report.sh        # Save SonarQube results to reports/
├── reports/sonar-report.md    # SonarQube report
└── docs/ASSIGNMENT2_STEPS.md  # Step-by-step setup on the VM
```

## 5. Deployment strategies

| Strategy | How | Rollback |
|---|---|---|
| Rolling update | 3 pods replaced one at a time, `maxUnavailable: 0`, readiness probe on `/health` | `kubectl rollout undo` (automatic on failure) |
| Blue-green | Two full deployments; the Service selector points at one colour; preview Service on the idle colour | Switch the selector back |
| Canary | 3 stable + 1 canary pod behind one Service (≈25 %) | Scale the canary to 0 |
| A/B testing | nginx router: `X-Variant` header → cookie → random 50/50, sticky cookie | Put variant B on A's image |
| Shadow | nginx `mirror` sends a copy of every request to the new version; its responses are discarded | Scale the shadow to 0 |

```bash
bash scripts/deploy.sh <strategy> <user>/aceest-fitness:3.2.4 [<user>/aceest-fitness:2.2.4]
bash scripts/promote.sh canary|ab-testing|shadow
bash scripts/rollback.sh <strategy>
bash scripts/endpoints.sh
```

## 6. Run locally

```bash
python3 -m venv venv && . venv/bin/activate
pip install -r requirements.txt
pytest -v --cov=app        # tests + coverage
flake8 app.py tests/       # lint
python app.py              # http://localhost:5000
APP_VERSION=1.1 python app.py   # run as another version
```

## 7. Branching and versioning

- `main` is always releasable; work happens on `feature/*` branches merged with `--no-ff`.
- Conventional Commits (`feat:`, `fix:`, `test:`, `ci:`, `deploy:`, `docs:`, `release:`).
- A release = change `VERSION`, commit `release: vX`, tag `vX`, push. Jenkins builds,
  pushes `<user>/aceest-fitness:X` and rolls it out.

Full setup instructions: [docs/ASSIGNMENT2_STEPS.md](docs/ASSIGNMENT2_STEPS.md).
