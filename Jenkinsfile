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

        SONAR_PROJECT_KEY = "rouissinour464_micro-service-api-gateway"
        SONAR_ORG         = "rouissinour464"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    set -eux
                    chmod +x mvnw
                    ./mvnw test
                '''
            }
        }

        stage('Integration Tests') {
            steps {
                sh '''
                    set -eux
                    ./mvnw verify
                '''
            }
        }

        stage('SonarCloud Analysis') {
            steps {
                withSonarQubeEnv('SonarCloud') {
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                        sh '''
                            set -eux

                            ./mvnw sonar:sonar \
                              -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                              -Dsonar.organization=${SONAR_ORG} \
                              -Dsonar.host.url=https://sonarcloud.io \
                              -Dsonar.token=${SONAR_TOKEN}
                        '''
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    set -eux
                    docker build -t ${IMAGE}:${TAG} .
                '''
            }
        }

        stage('Docker Push') {
            steps {
                withCredentials([
                    string(credentialsId: 'dockerhub-pass', variable: 'DOCKER_PASSWORD')
                ]) {
                    sh '''
                        set -eux

                        echo "$DOCKER_PASSWORD" | docker login -u ${REGISTRY} --password-stdin

                        docker push ${IMAGE}:${TAG}
                        docker tag ${IMAGE}:${TAG} ${IMAGE}:latest
                        docker push ${IMAGE}:latest

                        docker logout
                    '''
                }
            }
        }

        stage('Check Cluster') {
            steps {
                sh '''
                    set -eux
                    kubectl get nodes
                '''
            }
        }

        stage('Deploy App') {
            steps {
                sh '''
                    set -eux
                    kubectl apply -k k8s/app
                '''
            }
        }

        stage('Restart App') {
            steps {
                sh '''
                    set -eux
                    kubectl rollout restart deployment gateway-service -n ${NAMESPACE}
                    kubectl rollout status deployment gateway-service -n ${NAMESPACE}
                '''
            }
        }

        // ✅ DEPLOY LOGGING SAFE
        stage('Deploy Logging (Safe)') {
            steps {
                timeout(time: 3, unit: 'MINUTES') {
                    sh '''
                        set -eux

                        kubectl create namespace ${LOGGING_NS} \
                            --dry-run=client -o yaml | kubectl apply -f -

                        if kubectl get deployment opensearch -n ${LOGGING_NS} >/dev/null 2>&1; then
                            echo "✅ Logging déjà installé → SKIP"
                        else
                            echo "🚀 Installation logging"
                            kubectl apply -k k8s/logging
                        fi
                    '''
                }
            }
        }

        // ✅ WAIT SAFE (NE CASSE PAS LE PIPELINE)
        stage('Wait Logging Ready') {
            steps {
                sh '''
                    set -eux

                    if kubectl get deployment opensearch -n ${LOGGING_NS} >/dev/null 2>&1; then
                        echo "⏳ Waiting OpenSearch..."
                        kubectl rollout status deployment/opensearch -n ${LOGGING_NS} || true

                        echo "⏳ Waiting Dashboards..."
                        kubectl rollout status deployment/opensearch-dashboards -n ${LOGGING_NS} || true
                    else
                        echo "Logging not installed → skip"
                    fi
                '''
            }
        }

        // ✅ RESTART DÉSACTIVÉ
        stage('Restart Logging') {
            steps {
                sh '''
                    echo "⚠️ Restart logging disabled"
                '''
            }
        }

        stage('Check Pods') {
            steps {
                sh '''
                    set -eux

                    echo "=== APP ==="
                    kubectl get pods -n ${NAMESPACE}

                    echo "=== LOGGING ==="
                    kubectl get pods -n ${LOGGING_NS}
                '''
            }
        }

        // ✅ TEST LOGGING
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
            echo "✅ PIPELINE SUCCESS 🚀"
        }

        failure {
            echo "❌ PIPELINE FAILED"

            sh '''
                kubectl get pods -A || true
                kubectl logs -l app=opensearch -n ${LOGGING_NS} --tail=100 || true
                kubectl logs -l app=opensearch-dashboards -n ${LOGGING_NS} --tail=100 || true
                kubectl logs -l app=fluent-bit -n ${LOGGING_NS} --tail=100 || true
            '''
        }

        always {
            cleanWs()
        }
    }
}
