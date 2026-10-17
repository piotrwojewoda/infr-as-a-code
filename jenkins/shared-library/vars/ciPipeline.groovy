// vars/ciPipeline.groovy — global shared library "malina-ci"
//
// The single, enforced delivery pipeline of the malina platform.
// Stage order and the test gate are defined HERE, in the GitOps repository;
// application Jenkinsfiles only pass parameters and cannot skip, reorder or
// pin around the stages (global library: implicit, allowVersionOverride=false).
//
// Contract: specs/002-tests-before-deploy/contracts/pipeline.md
//
// Parameters:
//   config.app          (required) application name — image name + commit messages
//   config.testImage    (required) container image used to run ci/test.sh (linux/arm64!)
//   config.testDeps     (optional) [image: ..., command: ...] — dependency-install
//                                  step run in the same pod workspace before the tests
//   config.gitopsValues (optional) values file to bump; default clusters/malina/values/<app>.yaml
//   config.registry     (optional) default 192.168.68.52:30500 (in-cluster, plain HTTP;
//                                  change for the documented GHCR swap — research 001 D2)
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

    final String app = config.app
    final String testImage = config.testImage
    final Map testDeps = config.testDeps
    final String gitopsValues = config.gitopsValues ?: "clusters/malina/values/${app}.yaml"
    final String registry = config.registry ?: '192.168.68.52:30500'
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
  containers:
    - name: kaniko
      image: gcr.io/kaniko-project/executor:v1.24.0-debug
      command: ["/busybox/sleep"]
      args: ["99d"]
    - name: git
      image: alpine/git:2.49.1
      command: ["sleep"]
      args: ["99d"]
    - name: test
      image: ${testImage}
      command: ["sleep"]
      args: ["99d"]${depsContainer}
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
                              --insecure \\
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
        }

        post {
            success { echo "Released ${env.IMAGE}:${env.IMAGE_TAG} - ArgoCD will roll it out" }
            failure { echo 'Pipeline failed - the running deployment was NOT touched.' }
            aborted { echo 'Pipeline aborted (e.g. timeout) - treated as failed; the running deployment was NOT touched.' }
        }
    }
}
