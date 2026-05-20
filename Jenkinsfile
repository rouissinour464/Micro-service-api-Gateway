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

        // ✅ DEPLOY LOGGING SAFE (NO DELETE PVC)
        stage('Deploy Logging') {
            steps {
                timeout(time: 3, unit: 'MINUTES') {
                    sh '''
                        set -eux

                        kubectl create namespace ${LOGGING_NS} \
                            --dry-run=client -o yaml | kubectl apply -f -

                        kubectl apply -k k8s/logging
                    '''
                }
            }
        }

        // ✅ WAIT UNTIL SERVICES READY
        stage('Wait Logging Ready') {
            steps {
                sh '''
                    set -eux

                    kubectl rollout status deployment/opensearch -n ${LOGGING_NS}
                    kubectl rollout status deployment/opensearch-dashboards -n ${LOGGING_NS}
                '''
            }
        }

        stage('Restart Logging') {
            steps {
                sh '''
                    set -eux

                    kubectl rollout restart deployment/opensearch -n ${LOGGING_NS} || true
                    kubectl rollout restart deployment/opensearch-dashboards -n ${LOGGING_NS} || true
                    kubectl rollout restart daemonset/fluent-bit -n ${LOGGING_NS} || true
                '''
            }
        }

        stage('Check Pods') {
            steps {
                sh '''
                    set -eux

                    echo "=== APP PODS ==="
                    kubectl get pods -n ${NAMESPACE}

                    echo "=== LOGGING PODS ==="
                    kubectl get pods -n ${LOGGING_NS}
                '''
            }
        }

        // ✅ TEST LOGGING PIPELINE
        stage('Check Logs Pipeline') {
            steps {
                sh '''
                    set -eux

                    echo "=== GENERATE TEST LOG ==="
                    kubectl run log-test --image=busybox --restart=Never -- echo "test log pipeline" || true
                    sleep 5

                    echo "=== CHECK OPENSEARCH ==="
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
                echo "=== DEBUG PODS ==="
                kubectl get pods -A || true

                echo "=== OPENSEARCH LOGS ==="
                kubectl logs -l app=opensearch -n ${LOGGING_NS} --tail=100 || true

                echo "=== DASHBOARDS LOGS ==="
                kubectl logs -l app=opensearch-dashboards -n ${LOGGING_NS} --tail=100 || true

                echo "=== FLUENT BIT LOGS ==="
                kubectl logs -l app=fluent-bit -n ${LOGGING_NS} --tail=100 || true
            '''
        }

        always {
            cleanWs()
        }
    }
}
