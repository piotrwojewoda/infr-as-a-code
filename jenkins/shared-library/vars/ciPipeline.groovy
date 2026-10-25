// vars/ciPipeline.groovy — global shared library "malina-ci"
//
// The single, enforced delivery pipeline of the malina platform.
// Stage order and the test gate are defined HERE, in the GitOps repository;
// application Jenkinsfiles only pass parameters and cannot skip, reorder or
// pin around the stages (global library: implicit, allowVersionOverride=false).
//
// Contract: specs/002-tests-before-deploy/contracts/pipeline.md
// Deploy confirmation: specs/005-deploy-confirmation/spec.md
//
// Parameters:
//   config.app          (required) application name — image name + commit messages
//   config.testImage    (required) container image used to run ci/test.sh (linux/arm64!)
//   config.testDeps     (optional) [image: ..., command: ...] — dependency-install
//                                  step run in the same pod workspace before the tests
//   config.gitopsValues (optional) values file to bump; default clusters/malina/values/<app>.yaml
//   config.registry     (optional) default ghcr.io/piotrwojewoda (GitHub Container
//                                  Registry — spec 004; images are private, ARM64 only)
//   config.deploy       (required) [namespace, deployment, argoApp] — the final Deploy
//                                  stage waits until this Deployment runs the new tag;
//                                  green build == release is live (spec 005)
def call(Map config) {
    if (!config?.app) {
        error "ciPipeline: required parameter 'app' is missing (application name, e.g. 'demo-symfony-k3s')"
    }
    if (!config?.testImage) {
        error "ciPipeline: required parameter 'testImage' is missing (image used to run ci/test.sh, must support linux/arm64)"
    }
    if (config?.testDeps && (!config.testDeps.image || !config.testDeps.command)) {
        error "ciPipeline: 'testDeps' must look like [image: 'composer:2', command: 'composer install ...']"
    }
    if (!config?.deploy?.namespace || !config?.deploy?.deployment || !config?.deploy?.argoApp) {
        error "ciPipeline: 'deploy' must look like [namespace: 'demo', deployment: 'demo-symfony', argoApp: 'demo-symfony'] — the pipeline ends green only when the release is live (spec 005)"
    }

    final String app = config.app
    final String testImage = config.testImage
    final Map testDeps = config.testDeps
    final String gitopsValues = config.gitopsValues ?: "clusters/malina/values/${app}.yaml"
    final String registry = config.registry ?: 'ghcr.io/piotrwojewoda'
    final String deployNs = config.deploy.namespace
    final String deployName = config.deploy.deployment
    final String argoApp = config.deploy.argoApp
    int testStatus = 0

    // Optional dependency-install container, only when the app declares testDeps.
    final String depsContainer = testDeps ? """
    - name: deps
      image: ${testDeps.image}
      command: ["sleep"]
      args: ["99d"]""" : ''

    pipeline {
        agent {
            kubernetes {
                defaultContainer 'git'
                yaml """
apiVersion: v1
kind: Pod
metadata:
  labels: { app: jenkins-agent-${app} }
spec:
  restartPolicy: Never
  serviceAccountName: jenkins-agent   # spec 005: least-privilege RBAC (jenkins-rbac.yaml)
  containers:
    - name: kaniko
      image: gcr.io/kaniko-project/executor:v1.24.0-debug
      command: ["/busybox/sleep"]
      args: ["99d"]
      volumeMounts:
        - name: ghcr-push
          mountPath: /kaniko/.docker
    - name: git
      image: alpine/git:2.49.1
      command: ["sleep"]
      args: ["99d"]
    - name: deploy
      image: alpine/git:2.49.1        # same image as 'git' — no extra pull; kubectl is
      command: ["sleep"]              # fetched from dl.k8s.io at stage start (arm64,
      args: ["99d"]                   # version matched to the k3s server minor)
    - name: test
      image: ${testImage}
      command: ["sleep"]
      args: ["99d"]${depsContainer}
  volumes:
    - name: ghcr-push
      secret:
        secretName: ghcr-push
        items:
          - key: .dockerconfigjson
            path: config.json
"""
            }
        }

        options {
            disableConcurrentBuilds()
            timeout(time: 30, unit: 'MINUTES')   // research 002 D5: aborted == failed
        }

        stages {
            stage('Checkout') {
                steps {
                    container('git') {
                        checkout scm
                        script {
                            // the workspace is owned by the jnlp (jenkins) user;
                            // this container runs as root -> mark it safe for git
                            sh 'git config --global --add safe.directory "${WORKSPACE}"'
                            env.IMAGE_TAG = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                            env.IMAGE = "${registry}/${app}"
                            echo "Releasing ${env.IMAGE}:${env.IMAGE_TAG}"
                        }
                    }
                }
            }

            stage('Test') {
                steps {
                    timeout(time: 15, unit: 'MINUTES') {   // research 002 D5
                        script {
                            // FR-004: no declared test suite -> fail fast, before any build
                            if (!fileExists('ci/test.sh')) {
                                error 'ci/test.sh not found — an automated test suite is mandatory for deployment (contract: specs/002-tests-before-deploy/contracts/test-suite.md)'
                            }
                        }
                        script {
                            if (testDeps) {
                                container('deps') {
                                    sh testDeps.command
                                }
                            }
                        }
                        container('test') {
                            sh 'chmod +x ci/test.sh'
                            script {
                                testStatus = sh(returnStatus: true, script: './ci/test.sh')
                            }
                        }
                        script {
                            // FR-005: publish the report even when tests failed,
                            // so the run shows WHICH tests failed
                            if (fileExists('build/junit.xml')) {
                                junit 'build/junit.xml'
                            }
                            if (testStatus != 0) {
                                error "Test suite failed (exit ${testStatus}) — release blocked, the running deployment stays untouched"
                            }
                            if (!fileExists('build/junit.xml')) {
                                error 'ci/test.sh passed but build/junit.xml is missing — the test suite must write a JUnit report (contract: specs/002-tests-before-deploy/contracts/test-suite.md)'
                            }
                        }
                    }
                }
            }

            stage('Build & Push') {
                steps {
                    container('kaniko') {
                        sh '''
                            /kaniko/executor \\
                              --context="${WORKSPACE}" \\
                              --dockerfile=Dockerfile \\
                              --destination="${IMAGE}:${IMAGE_TAG}" \\
                              --destination="${IMAGE}:latest"
                        '''
                    }
                }
            }

            stage('Update GitOps') {
                steps {
                    container('git') {
                        withCredentials([usernamePassword(credentialsId: 'github-pat', usernameVariable: 'GIT_USER', passwordVariable: 'GITHUB_TOKEN')]) {
                            sh """
                                set -e
                                git clone "https://x-access-token:\${GITHUB_TOKEN}@github.com/piotrwojewoda/infr-as-a-code.git" infra
                                cd infra
                                sed -i "s|^  tag: .*|  tag: \\"\${IMAGE_TAG}\\"|" "${gitopsValues}"
                                git config user.name "Jenkins CI"
                                git config user.email "jenkins@kreciowo.pl"
                                git add "${gitopsValues}"
                                if git diff --cached --quiet; then
                                    echo "Tag already up to date - nothing to commit."
                                else
                                    git commit -m "chore(release): ${app} \${IMAGE_TAG}"
                                    git push origin main
                                fi
                            """
                        }
                    }
                }
            }

            // spec 005: green build == release is live. Nudge ArgoCD, wait
            // until the Deployment runs the new tag, block on the rollout.
            stage('Deploy') {
                steps {
                    container('deploy') {
                        withEnv(["DEPLOY_NS=${deployNs}", "DEPLOY_NAME=${deployName}", "ARGO_APP=${argoApp}"]) {
                            sh '''
                                set -e
                                wget -q https://dl.k8s.io/release/v1.36.4/bin/linux/arm64/kubectl \
                                  -O /usr/local/bin/kubectl
                                chmod +x /usr/local/bin/kubectl

                                kubectl -n argocd annotate application "$ARGO_APP" \
                                  argocd.argoproj.io/refresh=hard --overwrite

                                echo "Waiting for $DEPLOY_NS/$DEPLOY_NAME to run :$IMAGE_TAG"
                                IMG=""
                                for i in $(seq 1 36); do
                                    IMG=$(kubectl -n "$DEPLOY_NS" get deployment "$DEPLOY_NAME" \
                                      -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
                                    echo "  [$i] image: ${IMG:-<not found>}"
                                    case "$IMG" in *:"$IMAGE_TAG") break ;; esac
                                    sleep 10
                                done
                                case "$IMG" in
                                    *:"$IMAGE_TAG") ;;
                                    *) echo "TIMEOUT: deployment did not pick up :$IMAGE_TAG in 6 min"; exit 1 ;;
                                esac

                                kubectl -n "$DEPLOY_NS" rollout status "deployment/$DEPLOY_NAME" --timeout=5m
                                echo "DEPLOY CONFIRMED: $IMG is live"
                            '''
                        }
                    }
                }
            }
        }

        post {
            success { echo "Deployed and verified: ${env.IMAGE}:${env.IMAGE_TAG} is live on malina (spec 005)" }
            failure { echo 'Pipeline failed - the previous deployment keeps running (GitOps tag is the only thing that may have advanced).' }
            aborted { echo 'Pipeline aborted (e.g. timeout) - treated as failed; the previous deployment keeps running.' }
        }
    }
}
