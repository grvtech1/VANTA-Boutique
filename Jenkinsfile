// =============================================================================
// VANTA Boutique — Jenkins CI/CD (declarative pipeline)
// -----------------------------------------------------------------------------
// Mirrors the GitHub Actions pipeline in Jenkins: vet + race tests for the Go
// reviews service, multi-service Docker builds, a Trivy image scan, and a
// branch-gated push to Docker Hub. Build, test, scan, ship — nothing reaches a
// registry unless tests and the scan pass on `main`.
// =============================================================================
pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        REGISTRY  = 'docker.io/grvp1'
        // Full git SHA — identical tag scheme to the GitHub Actions CD pipeline, so
        // scripts/bump-image-tags.sh / promote.sh work with images from either CI.
        IMAGE_TAG = "${env.GIT_COMMIT ?: 'local'}"
        SERVICES  = 'reviewsservice frontend productcatalogservice'
        // Add a 'dockerhub' username/password credential in Jenkins for the push stage.
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                sh 'git --no-pager log -1 --oneline'
            }
        }

        stage('Reviews Service — Vet & Race Tests') {
            agent {
                docker { image 'golang:1.25'; reuseNode true }
            }
            steps {
                dir('src/reviewsservice') {
                    sh '''
                        go vet ./...
                        go test -race -count=1 -coverprofile=coverage.out ./...
                        go tool cover -func=coverage.out | tail -1
                    '''
                }
            }
        }

        stage('Build Images') {
            steps {
                script {
                    env.SERVICES.split(' ').each { svc ->
                        sh "docker build -t ${REGISTRY}/${svc}:${IMAGE_TAG} src/${svc}"
                    }
                }
            }
        }

        stage('Security Scan (Trivy)') {
            steps {
                sh '''
                    set -e
                    for svc in $SERVICES; do
                      echo "--- Trivy gate (CRITICAL, fixable): ${svc} ---"
                      trivy image --severity CRITICAL --ignore-unfixed --no-progress \
                            --exit-code 1 "${REGISTRY}/${svc}:${IMAGE_TAG}"
                      echo "--- Trivy report (HIGH): ${svc} ---"
                      trivy image --severity HIGH --ignore-unfixed --no-progress \
                            --exit-code 0 "${REGISTRY}/${svc}:${IMAGE_TAG}"
                    done
                '''
            }
        }

        stage('Push to Registry') {
            when { branch 'main' }
            steps {
                withCredentials([usernamePassword(
                        credentialsId: 'dockerhub',
                        usernameVariable: 'DH_USER',
                        passwordVariable: 'DH_PASS')]) {
                    sh '''
                        set -e
                        echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                        # Immutable SHA tags only — no :latest (see docs/DECISIONS.md #2).
                        for svc in $SERVICES; do
                          docker push "${REGISTRY}/${svc}:${IMAGE_TAG}"
                        done
                        docker logout
                        echo "GitOps: scripts/bump-image-tags.sh kustomize/overlays/staging/kustomization.yaml ${IMAGE_TAG}"
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'docker image prune -f || true'
            cleanWs()
        }
        success { echo "✅ Pipeline succeeded — images tagged ${IMAGE_TAG}" }
        failure { echo "❌ Pipeline failed — check the failing stage's logs" }
    }
}
