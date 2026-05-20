pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        timestamps()
    }

    triggers {
        githubPush()
        cron('H */6 * * *')
    }

    tools {
        jdk 'JDK21'
    }

    environment {
        REGISTRY   = "nour292"
        IMAGE      = "${REGISTRY}/api-gateway"
        TAG        = "${BUILD_NUMBER}"

        KUBECONFIG = "/var/lib/jenkins/.kube/config"

        NAMESPACE  = "gestion-projet"
        LOGGING_NS = "logging"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build & Test') {
            steps {
                sh '''
                    set -eux
                    chmod +x mvnw
                    ./mvnw clean verify
                '''
            }
        }

        stage('Docker Build & Push') {
            steps {
                withCredentials([string(credentialsId: 'dockerhub-pass', variable: 'DOCKER_PASSWORD')]) {
                    sh '''
                        set -eux

                        docker build -t ${IMAGE}:${TAG} .
                        echo "$DOCKER_PASSWORD" | docker login -u ${REGISTRY} --password-stdin

                        docker push ${IMAGE}:${TAG}
                        docker tag ${IMAGE}:${TAG} ${IMAGE}:latest
                        docker push ${IMAGE}:latest

                        docker logout
                    '''
                }
            }
        }

        stage('Deploy App') {
            steps {
                sh '''
                    set -eux

                    kubectl apply -k k8s/app

                    kubectl rollout restart deployment gateway-service -n ${NAMESPACE}
                    kubectl rollout status deployment gateway-service -n ${NAMESPACE}
                '''
            }
        }

        // ✅ DEPLOY LOGGING UNIQUEMENT SI PAS EXISTANT
        stage('Init Logging (one-time)') {
            steps {
                sh '''
                    set -eux

                    # Vérifie si OpenSearch existe déjà
                    if kubectl get deployment opensearch -n ${LOGGING_NS} >/dev/null 2>&1; then
                        echo "✅ Logging déjà installé → SKIP"
                    else
                        echo "🚀 Installation Logging (1 seule fois)"
                        kubectl create namespace ${LOGGING_NS} || true
                        kubectl apply -k k8s/logging
                    fi
                '''
            }
        }

        stage('Check Pods') {
            steps {
                sh '''
                    echo "=== APP ==="
                    kubectl get pods -n ${NAMESPACE}

                    echo "=== LOGGING ==="
                    kubectl get pods -n ${LOGGING_NS}
                '''
            }
        }

        stage('Check Logs Pipeline') {
            steps {
                sh '''
                    set -eux

                    kubectl run log-test --image=busybox --restart=Never -- echo "test log pipeline" || true
                    sleep 5

                    kubectl port-forward -n ${LOGGING_NS} svc/opensearch 9200:9200 > /dev/null 2>&1 &
                    sleep 5

                    curl -s localhost:9200/_cat/indices?v || true
                '''
            }
        }
    }

    post {
        success {
            echo "✅ PIPELINE SUCCESS ✅"
        }

        failure {
            echo "❌ PIPELINE FAILED"

            sh '''
                kubectl get pods -A || true
                kubectl logs -n ${LOGGING_NS} -l app=opensearch --tail=100 || true
            '''
        }
    }
}
