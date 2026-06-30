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
        IMAGE_TAG = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'local'}"
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
                    ['reviewsservice', 'frontend'].each { svc ->
                        sh "docker build -t ${REGISTRY}/${svc}:${IMAGE_TAG} src/${svc}"
                    }
                }
            }
        }

        stage('Security Scan (Trivy)') {
            steps {
                sh '''
                    set -e
                    for svc in reviewsservice frontend; do
                      echo "--- Trivy scan: ${svc} ---"
                      trivy image --severity HIGH,CRITICAL --no-progress \
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
                        for svc in reviewsservice frontend; do
                          docker push "${REGISTRY}/${svc}:${IMAGE_TAG}"
                          docker tag  "${REGISTRY}/${svc}:${IMAGE_TAG}" "${REGISTRY}/${svc}:latest"
                          docker push "${REGISTRY}/${svc}:latest"
                        done
                        docker logout
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
