pipeline {
    agent any

    triggers {
        githubPush()
        cron('H */10 * * *')
    }

    options {
        timestamps()
    }

    tools {
        jdk 'JDK21'
    }

    environment {
        REGISTRY          = "nour292"
        IMAGE             = "${REGISTRY}/api-gateway"
        TAG               = "${BUILD_NUMBER}"

        KUBECONFIG        = "/var/lib/jenkins/.kube/config"

        SONAR_PROJECT_KEY = "rouissinour464_micro-service-api-gateway"
        SONAR_ORG         = "rouissinour464"

        LOGGING_NAMESPACE = "logging"
        APP_NAMESPACE     = "gestion-projet"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build + Test + Sonar') {
            steps {

                withSonarQubeEnv('SonarCloud') {

                    withCredentials([
                        string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')
                    ]) {

                        sh '''
                            set -eux

                            chmod +x mvnw

                            ./mvnw clean verify sonar:sonar \
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

        stage('Docker Build & Push') {
            steps {

                withCredentials([
                    string(credentialsId: 'dockerhub-pass', variable: 'DOCKER_PASSWORD')
                ]) {

                    sh '''
                        set -eux

                        echo "$DOCKER_PASSWORD" | docker login \
                            -u ${REGISTRY} \
                            --password-stdin

                        docker build -t ${IMAGE}:${TAG} .

                        docker tag ${IMAGE}:${TAG} ${IMAGE}:latest

                        docker push ${IMAGE}:${TAG}
                        docker push ${IMAGE}:latest

                        docker logout
                    '''
                }
            }
        }

        stage('Check Cluster Nodes') {
            steps {

                sh '''
                    set -eux
                    kubectl get nodes
                '''
            }
        }

        stage('Deploy Logging Stack') {
            steps {

                sh '''
                    set -eux

                    echo "📦 Création namespace logging..."

                    kubectl create namespace ${LOGGING_NAMESPACE} \
                        --dry-run=client -o yaml | kubectl apply -f -

                    echo "🚀 Déploiement stack logging..."

                    kubectl apply -k k8s/logging

                    echo "🔄 Restart OpenSearch..."
                    kubectl rollout restart deployment/opensearch \
                        -n ${LOGGING_NAMESPACE} || true

                    echo "🔄 Restart Dashboards..."
                    kubectl rollout restart deployment/opensearch-dashboards \
                        -n ${LOGGING_NAMESPACE} || true

                    echo "🔄 Restart Fluent Bit..."
                    kubectl rollout restart daemonset/fluent-bit \
                        -n ${LOGGING_NAMESPACE} || true

                    echo "⏳ Attente OpenSearch..."
                    kubectl rollout status deployment/opensearch \
                        --namespace=${LOGGING_NAMESPACE} \
                        --timeout=300s

                    echo "⏳ Attente Dashboards..."
                    kubectl rollout status deployment/opensearch-dashboards \
                        --namespace=${LOGGING_NAMESPACE} \
                        --timeout=600s

                    echo "⏳ Attente Fluent Bit..."
                    kubectl rollout status daemonset/fluent-bit \
                        --namespace=${LOGGING_NAMESPACE} \
                        --timeout=180s

                    echo "✅ Stack logging prête"

                    kubectl get pods -n ${LOGGING_NAMESPACE}
                '''
            }
        }

        stage('Deploy Application') {
            steps {

                sh '''
                    set -eux

                    echo "📦 Création namespace application..."

                    kubectl create namespace ${APP_NAMESPACE} \
                        --dry-run=client -o yaml | kubectl apply -f -

                    echo "🚀 Déploiement application..."

                    kubectl apply -k k8s/app
                '''
            }
        }

        stage('Rollout Restart') {
            steps {

                sh '''
                    set -eux

                    kubectl rollout restart deployment gateway-service \
                        -n ${APP_NAMESPACE}

                    kubectl rollout status deployment gateway-service \
                        -n ${APP_NAMESPACE} \
                        --timeout=300s
                '''
            }
        }

        stage('Verify Logging') {
            steps {

                sh '''
                    set -eux

                    echo "⏳ Attente indexation Fluent Bit..."
                    sleep 20

                    OPENSEARCH_POD=$(kubectl get pod \
                        --namespace=${LOGGING_NAMESPACE} \
                        --selector=app=opensearch \
                        --output=jsonpath="{.items[0].metadata.name}")

                    echo "📊 Santé OpenSearch"

                    kubectl exec ${OPENSEARCH_POD} \
                        --namespace=${LOGGING_NAMESPACE} \
                        -- curl -s \
                        "http://localhost:9200/_cluster/health?pretty"

                    echo "📚 Indices OpenSearch"

                    kubectl exec ${OPENSEARCH_POD} \
                        --namespace=${LOGGING_NAMESPACE} \
                        -- curl -s \
                        "http://localhost:9200/_cat/indices?v"

                    echo "🌐 OpenSearch Dashboards"
                    echo "http://<NODE_IP>:30601"
                '''
            }
        }
    }

    post {

        success {

            echo '''
✅ PIPELINE SUCCESS 🚀

🌐 OpenSearch Dashboards:
http://<NODE_IP>:30601
'''
        }

        failure {

            sh '''
                echo "=============================="
                echo "❌ PIPELINE FAILURE"
                echo "=============================="

                echo ""
                echo "=== Namespace gestion-projet ==="

                kubectl get pods -n ${APP_NAMESPACE} || true
                kubectl describe pods -n ${APP_NAMESPACE} || true
                kubectl get events -n ${APP_NAMESPACE} || true

                echo ""
                echo "=== Namespace logging ==="

                kubectl get pods -n ${LOGGING_NAMESPACE} || true
                kubectl get pvc -n ${LOGGING_NAMESPACE} || true

                echo ""
                echo "=== Describe OpenSearch ==="

                kubectl describe deployment opensearch \
                    -n ${LOGGING_NAMESPACE} || true

                echo ""
                echo "=== Describe Dashboards ==="

                kubectl describe deployment opensearch-dashboards \
                    -n ${LOGGING_NAMESPACE} || true

                echo ""
                echo "=== Describe Fluent Bit ==="

                kubectl describe daemonset fluent-bit \
                    -n ${LOGGING_NAMESPACE} || true

                echo ""
                echo "=== Logs OpenSearch ==="

                OPENSEARCH_POD=$(kubectl get pod \
                    --namespace=${LOGGING_NAMESPACE} \
                    --selector=app=opensearch \
                    --output=jsonpath="{.items[0].metadata.name}" \
                    2>/dev/null || echo "")

                if [ -n "$OPENSEARCH_POD" ]; then

                    kubectl logs ${OPENSEARCH_POD} \
                        --namespace=${LOGGING_NAMESPACE} \
                        --tail=100 || true
                fi

                echo ""
                echo "=== Logs Dashboards ==="

                DASHBOARD_POD=$(kubectl get pod \
                    --namespace=${LOGGING_NAMESPACE} \
                    --selector=app=opensearch-dashboards \
                    --output=jsonpath="{.items[0].metadata.name}" \
                    2>/dev/null || echo "")

                if [ -n "$DASHBOARD_POD" ]; then

                    kubectl logs ${DASHBOARD_POD} \
                        --namespace=${LOGGING_NAMESPACE} \
                        --tail=100 || true

                    kubectl describe pod ${DASHBOARD_POD} \
                        --namespace=${LOGGING_NAMESPACE} || true
                fi

                echo ""
                echo "=== Logs Fluent Bit ==="

                kubectl logs daemonset/fluent-bit \
                    --namespace=${LOGGING_NAMESPACE} \
                    --tail=100 || true
            '''
        }

        always {
            cleanWs()
        }
    }
}