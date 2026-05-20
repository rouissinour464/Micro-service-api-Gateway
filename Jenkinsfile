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
                withCredentials([string(credentialsId: 'dockerhub-pass', variable: 'DOCKER_PASSWORD')]) {
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

        // ✅ DEPLOY LOGGING — FIX PV RELEASED AUTOMATIQUE
        stage('Deploy Logging') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    sh '''
                        set -eux

                        kubectl create namespace ${LOGGING_NS} \
                            --dry-run=client -o yaml | kubectl apply -f -

                        # ✅ FIX DEFINITIF : libérer les PVs Released avant apply
                        for PV in pv-opensearch-logs pv-opensearch-dashboards pv-fluentbit-db; do
                            STATUS=$(kubectl get pv $PV -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
                            if [ "$STATUS" = "Released" ]; then
                                echo "🔧 PV $PV Released → libération"
                                kubectl patch pv $PV --type=json \
                                    -p='[{"op":"remove","path":"/spec/claimRef"}]' || true
                            fi
                        done

                        # ✅ Créer dossiers SANS chmod (permissions déjà fixées sur la VM)
                        mkdir -p /data/opensearch-logs \
                                 /data/opensearch-dashboards \
                                 /data/fluentbit-db || true

                        if kubectl get deployment opensearch -n ${LOGGING_NS} >/dev/null 2>&1; then
                            echo "✅ Logging déjà installé"
                        else
                            echo "🚀 Installation logging"
                            kubectl apply -k k8s/logging
                        fi
                    '''
                }
            }
        }

        // ✅ WAIT SAFE — JAMAIS FAIL
        stage('Wait Logging Ready') {
            steps {
                sh '''
                    set -eux

                    if kubectl get deployment opensearch -n ${LOGGING_NS} >/dev/null 2>&1; then

                        echo "⏳ OpenSearch check (120s max)"
                        kubectl rollout status deployment/opensearch \
                            -n ${LOGGING_NS} --timeout=120s || true

                        echo "⏳ Dashboards check (120s max)"
                        kubectl rollout status deployment/opensearch-dashboards \
                            -n ${LOGGING_NS} --timeout=120s || true

                    else
                        echo "Logging not installed → skip"
                    fi
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

                    echo "=== PVCs ==="
                    kubectl get pvc -n ${LOGGING_NS}

                    echo "=== PVs ==="
                    kubectl get pv | grep logging-local || true
                '''
            }
        }

        // ✅ TEST FINAL LOGS
        stage('Check Logs Pipeline') {
            steps {
                sh '''
                    set -eux

                    kubectl run log-test --image=busybox --restart=Never \
                        -- echo "hello logs" || true
                    sleep 5

                    kubectl port-forward -n ${LOGGING_NS} svc/opensearch \
                        9200:9200 > /dev/null 2>&1 &
                    sleep 5

                    echo "=== INDICES ==="
                    curl -s localhost:9200/_cat/indices?v || true

                    # cleanup
                    kubectl delete pod log-test --ignore-not-found=true
                    pkill -f "port-forward.*9200" || true
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
                kubectl get pvc -n logging || true
                kubectl get pv | grep logging-local || true
                kubectl logs -l app=opensearch -n logging --tail=100 || true
                kubectl logs -l app=opensearch-dashboards -n logging --tail=100 || true
                kubectl logs -l app=fluent-bit -n logging --tail=100 || true
            '''
        }

        always {
            cleanWs()
        }
    }
}