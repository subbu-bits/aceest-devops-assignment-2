# Assignment 2: step-by-step on the college VM

Run every command in the VM terminal as your normal lab user, unless it says `sudo`.
Commands in a box can be copied and pasted as one block.

📸 means take a screenshot for the report.

**Overview**

| Part | What | Time |
|---|---|---|
| 0 | Check the VM | 5 min |
| 1 | New GitHub repo + copy the code | 15 min |
| 2 | Commit on feature branches | 10 min |
| 3 | Minikube + kubectl | 15 min |
| 4 | SonarQube | 15 min |
| 5 | Docker Hub | 5 min |
| 6 | Jenkins setup + first build | 30 min |
| 7 | Release all 5 versions through Jenkins | 30 min |
| 8 | The 5 deployment strategies + rollback | 45 min |
| 9 | SonarQube report, endpoints, final push | 10 min |

---

## Part 0 - Check the VM

```bash
free -h          # RAM: SonarQube + Jenkins + Minikube need about 6-8 GB
nproc            # CPUs: 2 or more
df -h ~          # 10 GB free disk or more
docker version --format '{{.Server.Version}}'
groups           # your user should be in the "docker" group
curl -sI https://hub.docker.com | head -1    # internet works
```

If RAM is under 6 GB, use `--memory=2500` in Part 3, and stop SonarQube
(`docker stop sonarqube`) while you do Part 8.

If `docker` is not in your groups: run `sudo usermod -aG docker $USER`, then log out and back in.

---

## Part 1 - New GitHub repo and copy the code

**1.1** On github.com, create a new **public** repository called
`aceest-devops-assignment-2`. Leave it empty: no README, no .gitignore.

**1.2** Clone your Assignment 1 repo under the new name, so the history carries over, and point it at the new repo:

```bash
cd ~
git clone git@github.com:subbu-bits/aceest-devops-assignment-1.git aceest-devops-assignment-2
cd ~/aceest-devops-assignment-2
git remote set-url origin git@github.com:subbu-bits/aceest-devops-assignment-2.git
git push -u origin main --tags
```

**1.3** Download `aceest-devops-assignment-2.zip` from the Claude chat in the VM's browser.
It goes to `~/Downloads`. Unzip it over the repo:

```bash
cd ~/aceest-devops-assignment-2
rm -rf /tmp/a2 && unzip -q ~/Downloads/aceest-devops-assignment-2.zip -d /tmp/a2
cp -r /tmp/a2/aceest-devops-assignment-2/. ~/aceest-devops-assignment-2/
chmod +x scripts/*.sh
git status
```

> **If you can't download in the VM:** on your laptop, unzip and upload the files into the
> new GitHub repo (**Add file → Upload files**), then on the VM run
> `git pull` and skip Part 2.

**1.4** Run the tests locally before committing:

```bash
cd ~/aceest-devops-assignment-2
python3 -m venv venv && . venv/bin/activate
pip install -r requirements.txt
pytest -q --cov=app          # expect: 82 passed
flake8 app.py tests/         # expect: no output
deactivate
```

📸 `82 passed` with the coverage table.

---

## Part 2 - Commit on feature branches

Same style as Assignment 1. Each block makes a branch, commits only its files, and merges into `main`.

```bash
cd ~/aceest-devops-assignment-2
git checkout -b feature/versioning
git add app.py VERSION tests/
git commit -m "feat: version registry mapping Tkinter versions 1.0-3.2.4 and /version endpoint"
git checkout main && git merge --no-ff feature/versioning -m "Merge feature/versioning"

git checkout -b feature/sonarqube
git add sonar-project.properties requirements.txt scripts/sonar_report.sh
git commit -m "ci: add pytest-cov coverage and SonarQube configuration"
git checkout main && git merge --no-ff feature/sonarqube -m "Merge feature/sonarqube"

git checkout -b feature/kubernetes
git add k8s/ scripts/
git commit -m "deploy: Kubernetes manifests and scripts for rolling, blue-green, canary, A/B and shadow"
git checkout main && git merge --no-ff feature/kubernetes -m "Merge feature/kubernetes"

git checkout -b feature/jenkins-cd
git rm -q DockerFile          # duplicate of Dockerfile from Assignment 1
git add Jenkinsfile Dockerfile .dockerignore .gitignore
git commit -m "ci: Jenkins CD pipeline - SonarQube gate, Docker Hub push, K8s deploy and rollback"
git checkout main && git merge --no-ff feature/jenkins-cd -m "Merge feature/jenkins-cd"

git checkout -b docs/assignment-2
git add README.md docs/
git commit -m "docs: Assignment 2 README and setup guide"
git checkout main && git merge --no-ff docs/assignment-2 -m "Merge docs/assignment-2"

git status            # should say "nothing to commit"
git push origin main feature/versioning feature/sonarqube feature/kubernetes feature/jenkins-cd docs/assignment-2
git log --oneline --graph | head -20
```

📸 `git log --graph`. GitHub Actions also runs on these pushes (📸 the green run).

---

## Part 3 - Minikube and kubectl

```bash
cd /tmp
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
kubectl version --client
minikube version
```

Start the cluster. Lower `--memory` if the VM is small.

```bash
minikube start --driver=docker --cpus=2 --memory=3072
kubectl get nodes          # STATUS Ready
minikube ip                # usually 192.168.49.2
```

Let the `jenkins` user use the cluster. This copies your kubeconfig with the certificates embedded:

```bash
sudo mkdir -p /var/lib/jenkins/.kube
kubectl config view --flatten --minify | sudo tee /var/lib/jenkins/.kube/config >/dev/null
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube
sudo chmod 600 /var/lib/jenkins/.kube/config
sudo -u jenkins kubectl get nodes      # must show the node as Ready
```

> If Jenkins' home is not `/var/lib/jenkins`, check with `getent passwd jenkins | cut -d: -f6`.
>
> After a VM restart, run `minikube start` again before building.

📸 `kubectl get nodes` and `sudo -u jenkins kubectl get nodes`.

---

## Part 4 - SonarQube

**4.1** Start SonarQube in Docker:

```bash
sudo sysctl -w vm.max_map_count=524288
sudo sysctl -w fs.file-max=131072
docker run -d --name sonarqube --restart unless-stopped -p 9000:9000 \
  --add-host=host.docker.internal:host-gateway \
  -v sonarqube_data:/opt/sonarqube/data \
  -v sonarqube_extensions:/opt/sonarqube/extensions \
  -v sonarqube_logs:/opt/sonarqube/logs \
  sonarqube:community
# wait 1-2 minutes, until this prints "UP":
until curl -s localhost:9000/api/system/status | grep -q '"UP"'; do sleep 5; echo waiting...; done; echo UP
```

**4.2** In the browser, open http://localhost:9000 and log in as `admin` / `admin`.
It asks for a new password; set one.

**4.3** Create a token: **My Account (top right) → Security → Generate Tokens**.
- Name: `jenkins`
- Type: **Global Analysis Token** (or User Token)
- Click **Generate** and **copy the token**. You need it in Part 6 and Part 9.

**4.4** Add a webhook so SonarQube tells Jenkins the quality gate result:
**Administration → Configuration → Webhooks → Create**
- Name: `jenkins`
- URL: `http://host.docker.internal:8080/sonarqube-webhook/`  (the trailing `/` matters)

---

## Part 5 - Docker Hub

1. Sign up at https://hub.docker.com if you have no account. Your **username** is used below.
2. **Account settings → Personal access tokens → Generate new token**, with access *Read & Write*. Copy it.
3. Log in on the VM. Paste the token when it asks for a password:

```bash
docker login -u YOUR_DOCKERHUB_USERNAME
```

There's no need to create the repository; the first push creates `YOUR_DOCKERHUB_USERNAME/aceest-fitness`.

**5.4** Put your username in the Jenkinsfile and push:

```bash
cd ~/aceest-devops-assignment-2
sed -i "s/DOCKERHUB_USER = 'CHANGE_ME'/DOCKERHUB_USER = 'YOUR_DOCKERHUB_USERNAME'/" Jenkinsfile
grep DOCKERHUB_USER Jenkinsfile | head -1
git commit -am "ci: set Docker Hub repository"
git push origin main
```

---

## Part 6 - Jenkins

Open http://localhost:8080.

**6.1 Plugin.** Go to **Manage Jenkins → Plugins → Available plugins**, search **SonarQube Scanner**, install it, and restart Jenkins when it finishes.
(*Pipeline*, *Git*, *Credentials Binding* and *JUnit* were already used in Assignment 1.)

**6.2 Credentials.** Go to **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**:

| Kind | ID | Values |
|---|---|---|
| Username with password | `dockerhub-creds` | Username = Docker Hub username, Password = Docker Hub token |
| Secret text | `sonar-token` | Secret = SonarQube token from 4.3 |

The IDs must be exactly these.

**6.3 SonarQube server.** Go to **Manage Jenkins → System → SonarQube servers**:
- Tick **Environment variables**
- **Add SonarQube**: Name `sonarqube`, Server URL `http://localhost:9000`, token `sonar-token`
- Click **Save**

**6.4 Scanner tool.** Go to **Manage Jenkins → Tools → SonarQube Scanner installations → Add**:
- Name `SonarScanner`
- Tick **Install automatically** (latest version)
- Click **Save**

**6.5 Pipeline job.** Go to **New Item**, enter the name `aceest-cicd`, choose **Pipeline**, and click **OK**:
- **Build Triggers**: leave empty. The Jenkinsfile sets Poll SCM `H/5 * * * *` itself.
- **Pipeline**: choose *Pipeline script from SCM*
  - SCM: Git
  - Repository URL: `https://github.com/subbu-bits/aceest-devops-assignment-2.git`
  - Branch: `*/main`
  - Script Path: `Jenkinsfile`
- Click **Save**

**6.6 First build.** Click **Build Now**. This builds version **1.0** and deploys it with a rolling update to the `aceest-rolling` namespace. It takes 3-6 minutes the first time (plugins and scanner download).

Check the result:

```bash
kubectl -n aceest-rolling get pods
curl -s http://$(minikube ip):30081/version; echo
```

After this first run, the job shows **Build with Parameters** (strategy choice).

📸 Stage view with all stages green, the SonarQube dashboard (http://localhost:9000), the Docker Hub repo page, and the archived artifacts on the build page.

> **Problems?** See the table at the end of this guide.

---

## Part 7 - Release all versions (git tags + Docker Hub + rolling updates)

Each release is: change `VERSION`, commit, tag, push. Jenkins notices within 5 minutes
(or click **Build Now**), then builds, tests, pushes `:<version>` to Docker Hub, and
rolling-updates the cluster.

Tag the version Jenkins just built:

```bash
cd ~/aceest-devops-assignment-2
git tag -a v1.0 -m "v1.0 - fitness programs (Aceestver-1.0)"
git push origin v1.0
```

Watch the rolling update live in a **second terminal** during each release:

```bash
watch -n1 kubectl -n aceest-rolling get pods -o wide
```

Then release one version at a time. **Wait for each Jenkins build to finish before the next one.**

```bash
echo 1.1 > VERSION
git commit -am "release: v1.1 - calories and client profiles (Aceestver-1.1, 1.1.2)"
git tag -a v1.1 -m "v1.1" && git push origin main v1.1
```
```bash
echo 2.0.1 > VERSION
git commit -am "release: v2.0.1 - SQLite progress tracking (Aceestver-2.0.1 to 2.2.1)"
git tag -a v2.0.1 -m "v2.0.1" && git push origin main v2.0.1
```
```bash
echo 2.2.4 > VERSION
git commit -am "release: v2.2.4 - BMI and workout logging (Aceestver-2.2.4, 3.0.1)"
git tag -a v2.2.4 -m "v2.2.4" && git push origin main v2.2.4
```
```bash
echo 3.2.4 > VERSION
git commit -am "release: v3.2.4 - program generator (Aceestver-3.1.2, 3.2.4)"
git tag -a v3.2.4 -m "v3.2.4" && git push origin main v3.2.4
```

Check:

```bash
kubectl -n aceest-rolling rollout history deployment/aceest   # one revision per version
curl -s http://$(minikube ip):30081/version; echo              # 3.2.4
git tag                                                         # v1.0 ... v3.2.4
```

📸 The Jenkins build history (`#N v1.1 rolling`, …), the Docker Hub **Tags** tab with all 5 versions, `rollout history`, and `git tag`.

> **Short on time?** `bash scripts/release_all_versions.sh YOUR_DOCKERHUB_USERNAME` builds, tests and pushes all 5 images in one go. Still do the git tags.

---

## Part 8 - The 5 deployment strategies

Set two variables in **every new terminal**:

```bash
cd ~/aceest-devops-assignment-2
export IMG=YOUR_DOCKERHUB_USERNAME/aceest-fitness
export IP=$(minikube ip)
```

Each strategy goes from **2.2.4 (stable)** to **3.2.4 (new)**. You can run them from Jenkins
(**Build with Parameters** → `DEPLOY_STRATEGY` = blue-green, `STABLE_VERSION` = `2.2.4`) or by hand
as shown below. Use Jenkins for at least one of them for the screenshots.

A helper that counts which versions answer, used below:

```bash
count() { for i in $(seq ${2:-20}); do curl -s "$1/version" | python3 -c 'import json,sys;print(json.load(sys.stdin)["version"])'; done | sort | uniq -c; }
```

### 8.1 Rolling update (port 30081)

Open a second terminal that keeps calling the app, which proves zero downtime:

```bash
while true; do curl -s -o /dev/null -w "%{http_code} " http://$(minikube ip):30081/health; sleep 0.3; done
```

In the first terminal:

```bash
bash scripts/deploy.sh rolling $IMG:2.2.4      # go back to 2.2.4 ...
bash scripts/deploy.sh rolling $IMG:3.2.4      # ... and roll forward to 3.2.4
kubectl -n aceest-rolling rollout history deployment/aceest
```

The second terminal shows only `200`s, meaning no downtime. 📸

### 8.2 Blue-green (live 30082, preview 30092)

```bash
bash scripts/deploy.sh blue-green $IMG:3.2.4 $IMG:2.2.4
```

What happens: blue gets 2.2.4 and goes live, then green gets 3.2.4, is checked, and the switch happens.

```bash
count http://$IP:30082        # all 3.2.4 (live = green)
count http://$IP:30092        # all 2.2.4 (preview = old blue, still running)
kubectl -n aceest-bluegreen get pods -L color
bash scripts/rollback.sh blue-green   # instant switch back
count http://$IP:30082        # all 2.2.4 again
bash scripts/rollback.sh blue-green   # and forward again
```

📸 Before and after the switch, and the rollback.

### 8.3 Canary (port 30083)

```bash
bash scripts/deploy.sh canary $IMG:3.2.4 $IMG:2.2.4
kubectl -n aceest-canary get pods -L track
count http://$IP:30083 40     # about 30 x 2.2.4 and 10 x 3.2.4 (25%)
kubectl -n aceest-canary scale deployment/aceest-canary --replicas=3   # raise to 50%
count http://$IP:30083 40
bash scripts/promote.sh canary  # canary looks good: stable becomes 3.2.4
count http://$IP:30083 40       # all 3.2.4
```

📸 The `count` output at 25%, at 50%, and after promotion.

### 8.4 A/B testing (port 30084)

```bash
bash scripts/deploy.sh ab-testing $IMG:3.2.4 $IMG:2.2.4
curl -s -H 'X-Variant: A' http://$IP:30084/version; echo    # 2.2.4
curl -s -H 'X-Variant: B' http://$IP:30084/version; echo    # 3.2.4
count http://$IP:30084 40                                   # new users: ~50/50 split
# sticky: the same user (cookie jar) always gets the same variant
rm -f /tmp/jar; for i in 1 2 3 4 5; do curl -s -c /tmp/jar -b /tmp/jar -D - -o /dev/null http://$IP:30084/version | grep -i x-variant; done
```

📸 The header test, the 50/50 count, and sticky user.

### 8.5 Shadow (port 30085)

```bash
bash scripts/deploy.sh shadow $IMG:3.2.4 $IMG:2.2.4
count http://$IP:30085 10                      # users only ever get 2.2.4
kubectl -n aceest-shadow logs deploy/aceest-shadow | grep 'GET /version' | tail -10   # ...but 3.2.4 received the same 10 requests
kubectl -n aceest-shadow logs deploy/aceest-live | grep 'GET /version' | tail -10
# (the other log lines are Kubernetes' own /health probes)
```

📸 The count showing only 2.2.4, next to the shadow pod's log showing the same requests.

### 8.6 Automatic rollback on a failed deployment

Deploy an image that doesn't exist (simulates a broken release):

```bash
bash scripts/deploy.sh rolling $IMG:9.9.9     # waits 120 s, then rolls back by itself
kubectl -n aceest-rolling get pods            # old pods were never removed
curl -s http://$IP:30081/version; echo        # still 3.2.4
kubectl -n aceest-rolling rollout history deployment/aceest
```

Also try `bash scripts/deploy.sh blue-green $IMG:9.9.9`: live traffic is never switched.

📸 The "FAILED - rolling back" output.

### 8.7 Everything at once

```bash
bash scripts/endpoints.sh 20
kubectl get pods -A | grep aceest
```

📸 Both outputs. This is your list of endpoints for the submission.

---

## Part 9 - SonarQube report, endpoints, final push

```bash
cd ~/aceest-devops-assignment-2
bash scripts/sonar_report.sh YOUR_SONAR_TOKEN      # writes reports/sonar-report.md
git add reports/sonar-report.md
git commit -m "docs: add SonarQube report"
git push origin main     # Jenkins builds once more (green)
```

**Endpoint URLs to submit** (replace the IP with your `minikube ip`):

| Strategy | URL |
|---|---|
| Rolling update | http://192.168.49.2:30081 |
| Blue-green (live / preview) | http://192.168.49.2:30082 / :30092 |
| Canary | http://192.168.49.2:30083 |
| A/B testing | http://192.168.49.2:30084 |
| Shadow | http://192.168.49.2:30085 |

These URLs work inside the VM. If the evaluator must open them from outside, expose one through the VM's own IP. This only works if the lab network allows incoming connections:
`kubectl -n aceest-rolling port-forward --address 0.0.0.0 svc/aceest 8081:80` → `http://<VM-IP>:8081` (VM IP: `hostname -I`).

### Submission checklist

- [ ] GitHub repo public: app, `Jenkinsfile`, `Dockerfile`, `k8s/`, `tests/`, `reports/sonar-report.md`
- [ ] Tags `v1.0` … `v3.2.4` on GitHub
- [ ] Docker Hub repo with tags `1.0`, `1.1`, `2.0.1`, `2.2.4`, `3.2.4`, `latest`
- [ ] Jenkins: recent green builds (screenshots)
- [ ] SonarQube dashboard with Quality Gate *Passed* (screenshot)
- [ ] Endpoint URLs for all 5 strategies
- [ ] 2-3 page report (architecture, challenges, outcomes)

Write down every error you hit and how you fixed it. That's the "Challenges" section of the report.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Jenkins: `No tool named SonarScanner` | The name in Manage Jenkins → Tools must be exactly `SonarScanner` |
| Jenkins: `No SonarQube server 'sonarqube'` | Name in Manage Jenkins → System must be `sonarqube` |
| Quality Gate stage waits 5 min then fails | Webhook missing or unreachable. In SonarQube, open Administration → Webhooks → *jenkins* → last delivery. If it can't connect, use `http://<VM-IP>:8080/sonarqube-webhook/` (`hostname -I`). |
| SonarQube container keeps stopping | `docker logs sonarqube`. Usually `vm.max_map_count` (run the sysctl again) or not enough RAM. |
| `denied: requested access to the resource is denied` on push | Wrong `DOCKERHUB_USER` in Jenkinsfile, or the token lacks Write access |
| Deploy stage: `connection refused` / `Unable to connect to the server` | Minikube stopped (`minikube start`), or redo the jenkins kubeconfig copy in Part 3 |
| Pods `ImagePullBackOff` | The tag isn't on Docker Hub (check the Tags tab) or the repo is private (make it public) |
| `flake8` fails in Jenkins | Run `flake8 app.py tests/` locally, fix, then push |
| Version check fails: expected X got Y | The `VERSION` file wasn't committed (`git status`) |
| Clients created on one pod are missing on another | Expected: each pod has its own SQLite file. Mention it in the report (fix: a shared DB such as PostgreSQL). |
