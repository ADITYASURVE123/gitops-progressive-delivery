

# Updated Master Prompt: GitOps Progressive Delivery Platform (Argo CD + Argo Rollouts + Prometheus + Jenkins)

**Copy everything below into a coding agent (Claude Code, Cursor, Devin, etc.) to build a portfolio-grade DevOps project.**

---

## ROLE
Act as a Senior DevOps / Platform Engineer. Build a production-grade, interview-ready reference implementation of GitOps-driven Progressive Delivery using **Argo CD**, **Argo Rollouts**, and **Prometheus**, with **automated metric-based rollback**. The CI/CD engine is **Jenkins** (instead of GitHub Actions). The end result must be a public GitHub repository that a hiring manager can clone, run locally (`kind`/`minikube`), and understand within 10 minutes — code, pipelines, tests, and docs all included.

## REQUIRED AGENT SKILLS (confirm you have these before starting)
- Kubernetes (Deployments, Services, Ingress, RBAC, CRDs, kubectl, kustomize/Helm)
- Argo CD (Application/ApplicationSet CRDs, App-of-Apps pattern, sync waves, hooks)
- Argo Rollouts (canary + blue-green strategies, AnalysisTemplates, AnalysisRun, traffic management via Istio/Nginx/SMI)
- Prometheus + PromQL (writing SLO-based queries: error rate, latency p99, success rate) and Prometheus Operator (ServiceMonitor/PodMonitor CRDs)
- GitOps principles (declarative desired state, Git as source of truth, drift detection, no `kubectl apply` in CI)
- **CI/CD with Jenkins** — build, test, lint, scan, image push, GitOps repo update
- Containerization (multi-stage Dockerfiles, distroless/minimal base images)
- IaC (Terraform or Helm for cluster bootstrap) — optional but preferred
- Testing discipline: unit tests, integration tests, contract tests, and chaos/failure-injection tests that validate automatic rollback
- Observability (Grafana dashboards, Prometheus alerting rules, structured logging)
- Security basics (image scanning with Trivy, least-privilege RBAC, sealed-secrets/SOPS for secrets)
- Clear technical writing (README, ADRs, runbooks, diagrams via Mermaid)

If any of these are unfamiliar, research them first — do not fake configuration you don’t understand; every manifest must actually work.

## PROJECT GOAL
Deploy a simple two-service demo app (e.g., `api` + `frontend`, any language — Go or Node preferred for small images) where:

- Every merge to `main` builds a new container image, tagged with the Git SHA.
- A GitOps repo (or `/gitops` folder) is updated automatically with the new image tag (via Jenkins or Argo CD Image Updater).
- Argo CD detects the change and syncs it to the cluster.
- Argo Rollouts executes a canary rollout (primary demo) — and a blue-green rollout as a second, switchable strategy — shifting traffic in steps (e.g., 20% → 40% → 60% → 100%).
- At each step, an AnalysisTemplate queries Prometheus for error rate and p99 latency.
- If metrics breach thresholds, Argo Rollouts automatically aborts and rolls back — no human intervention.
- Everything is observable via a Grafana dashboard showing the rollout in real time.

## REPOSITORY STRUCTURE (produce exactly this, adjust only if justified in README)
```
gitops-progressive-delivery/
├── README.md                          # recruiter-facing overview, architecture diagram, demo GIF
├── ARCHITECTURE.md                    # deep-dive design doc + Mermaid diagrams
├── RUNBOOK.md                         # how to operate, how rollback works, how to debug a stuck rollout
├── docs/
│   ├── adr/                           # Architecture Decision Records (numbered, e.g. 0001-canary-vs-bluegreen.md)
│   └── demo.gif / demo.mp4
├── app/
│   ├── api/                           # sample service, instrumented with /metrics (Prometheus client lib)
│   │   ├── src/
│   │   ├── tests/                     # unit + integration tests
│   │   ├── Dockerfile
│   │   └── Makefile
│   └── frontend/ (optional second service)
├── ci/
│   └── jenkins/
│       ├── Jenkinsfile                # declarative pipeline: lint, test, build, scan, push, update gitops
│       └── setup/                     # Terraform or script to provision Jenkins (EC2 or pod)
├── gitops/
│   ├── apps/
│   │   ├── app-of-apps.yaml           # Argo CD App-of-Apps root
│   │   └── api-application.yaml       # Argo CD Application pointing at overlays/prod
│   ├── base/
│   │   ├── rollout-canary.yaml        # Argo Rollouts canary strategy
│   │   ├── rollout-bluegreen.yaml     # Argo Rollouts blue-green strategy
│   │   ├── service.yaml / service-preview.yaml / service-active.yaml
│   │   ├── analysis-template.yaml     # Prometheus success-rate + latency checks
│   │   └── kustomization.yaml
│   └── overlays/
│       ├── dev/
│       └── prod/
├── infra/
│   ├── terraform/ or kind/            # local cluster bootstrap (kind + metrics + argocd + rollouts + prometheus + grafana)
│   └── bootstrap.sh                   # single-command environment setup
├── observability/
│   ├── prometheus/rules/              # alerting + recording rules
│   └── grafana/dashboards/rollout-dashboard.json
├── tests/
│   ├── unit/
│   ├── integration/
│   └── chaos/
│       ├── inject-errors.sh           # forces the canary to fail (e.g., toggles a /fail endpoint or fault-injection sidecar)
│       └── verify-rollback.sh         # asserts Argo Rollouts aborted and reverted to stable within N minutes
└── Makefile                           # make bootstrap / make deploy / make test / make chaos-test / make destroy
```

## BUILD PHASES (execute in order, commit after each phase)

### Phase 1 — App & Containerization
Build a minimal HTTP service exposing `/health`, `/version`, and `/metrics` (Prometheus format: request count, error count, latency histogram). Include a hidden fault-injection flag/env var (`FAIL_RATE`) purely for demoing rollback safely. Write unit tests (>80% coverage target) and a multi-stage Dockerfile producing a small, non-root image. Add a linter and a Makefile with `make test`, `make build`, `make run`.

### Phase 2 — Local Cluster Bootstrap
Script (`bootstrap.sh` or Terraform) that spins up `kind`/`minikube` and installs: Argo CD, Argo Rollouts + kubectl plugin, a traffic layer (Nginx Ingress or Istio — pick the simpler one and justify in `ARCHITECTURE.md`), kube-prometheus-stack (Prometheus + Grafana + Alertmanager). Idempotent, single command, documented prerequisites.

### Phase 3 — GitOps Wiring
App-of-Apps Argo CD pattern. Argo CD Application(s) pointing at `gitops/overlays/prod`, auto-sync enabled, self-heal enabled, pruning enabled. No manual `kubectl apply` anywhere in the flow after bootstrap.

### Phase 4 — Progressive Delivery
Implement both:
- **Canary (primary):** stepped traffic shift with pauses, automated AnalysisRun at each step against Prometheus.
- **Blue-green:** pre-promotion analysis + manual/automated promotion, active/preview services.
AnalysisTemplate must check at minimum: HTTP success rate ≥ 99%, p99 latency ≤ threshold, over a defined interval with enough samples to avoid false positives. Failure of either metric = automatic abort + rollback to stable.

### Phase 5 — CI/CD with Jenkins
**Replace GitHub Actions with Jenkins.** On push to `main` (or via webhook), Jenkins runs:
1. Lint
2. Unit test
3. Build Docker image
4. Trivy image scan (fail on HIGH/CRITICAL)
5. Push image to registry
6. Update image tag in `gitops/overlays/prod` via a Git commit (or PR) — document which and why.
7. Argo CD takes it from there.

The pipeline must run tests in parallel where possible, and fail the build on any test failure. Include a `Jenkinsfile` in the repo. You may provision Jenkins on an AWS EC2 instance using Terraform (or run Jenkins as a pod in the `kind` cluster) — document the approach.

### Phase 6 — Chaos / Rollback Verification
Automated script that:
- Triggers a new rollout with `FAIL_RATE` deliberately elevated.
- Confirms Argo Rollouts begins the canary.
- Confirms the AnalysisRun detects the breach.
- Confirms Argo Rollouts aborts and traffic returns 100% to stable.
- Asserts total time-to-rollback is under a defined SLA (e.g., 3 minutes).
Wire this into a CI job (`make chaos-test`) so rollback behavior is regression-tested on every change to the AnalysisTemplate or rollout strategy — this proves the safety net actually works, not just that it's configured.

### Phase 7 — Observability
Grafana dashboard (checked into repo as JSON) showing: rollout progress, canary vs stable traffic split, error rate, latency, and analysis run status. Prometheus alerting rule for stuck/degraded rollouts.

### Phase 8 — Documentation
- `README.md`: one-paragraph pitch, architecture diagram (Mermaid), tech stack badges, quickstart (`make bootstrap && make deploy`), demo GIF/video, link to `ARCHITECTURE.md` and `RUNBOOK.md`.
- `ARCHITECTURE.md`: why canary vs blue-green, why these metrics, trade-offs considered, diagram of the full request/deploy flow.
- `RUNBOOK.md`: how to trigger a deploy, how to force a rollback manually, how to debug a stuck AnalysisRun, common failure modes.
- ADRs for at least 3 real decisions (traffic layer choice, rollback thresholds, CI update strategy).

## QUALITY BAR / DEFINITION OF DONE
- `make bootstrap && make deploy` works from a clean clone on a fresh machine.
- A bad deploy (`FAIL_RATE` up) is automatically rolled back with no human step, and this is proven by an automated test, not just a manual demo.
- CI pipeline is green, runs tests on every PR, blocks merge on failure.
- No secrets in plaintext in the repo.
- All manifests pass `kubeval`/`kubeconform` and `kustomize` build cleanly.
- `README` readable and complete in under 10 minutes, with a working demo GIF.
- Repo has commit history showing incremental, reviewable progress — not one giant commit.
- License, `CONTRIBUTING.md`, and a short "what I'd do next at scale" section (multi-cluster, progressive delivery for DBs, cost, SSO for Argo CD, OPA/Gatekeeper policies).

## OUTPUT INSTRUCTIONS FOR THE AGENT
Work phase by phase. After each phase, run and show the relevant tests/checks before moving on. If a tool or CRD version differs from what’s assumed here, state the substitution and why in `ARCHITECTURE.md` rather than silently deviating. Optimize for a real hiring manager reading this repo — correctness and clarity over cleverness.

---

**Note:** This prompt replaces GitHub Actions with Jenkins, while keeping all other elements (Argo CD, Argo Rollouts, Prometheus, chaos tests, docs) intact. The Jenkins pipeline should be the primary CI/CD engine, and you should document how Jenkins is provisioned (e.g., Terraform on AWS EC2 or a Jenkins pod in the `kind` cluster).