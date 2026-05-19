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
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
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
                withCredentials([string(credentialsId: 'dockerhub-pass', variable: 'DOCKER_PASSWORD')]) {
                    sh '''
                        set -eux
                        echo "$DOCKER_PASSWORD" | docker login -u ${REGISTRY} --password-stdin
                        docker build -t ${IMAGE}:${TAG} .
                        docker tag  ${IMAGE}:${TAG} ${IMAGE}:latest
                        docker push ${IMAGE}:${TAG}
                        docker push ${IMAGE}:latest
                        docker logout
                    '''
                }
            }
        }

        stage('Check Cluster Nodes') {
            steps {
                sh 'set -eux && kubectl get nodes'
            }
        }

        stage('Deploy Logging Stack') {
            steps {
                sh '''
                    set -eux
                    echo "📦 Déploiement de la stack logging..."
                    kubectl apply -k k8s/logging

                    echo "⏳ Attente OpenSearch..."
                    kubectl rollout status deployment/opensearch \
                        --namespace=${LOGGING_NAMESPACE} \
                        --timeout=180s

                    echo "⏳ Attente OpenSearch Dashboards..."
                    kubectl rollout status deployment/opensearch-dashboards \
                        --namespace=${LOGGING_NAMESPACE} \
                        --timeout=180s

                    echo "⏳ Attente Fluent Bit..."
                    kubectl rollout status daemonset/fluent-bit \
                        --namespace=${LOGGING_NAMESPACE} \
                        --timeout=120s

                    echo "✅ Stack logging déployée !"
                    kubectl get pods -n ${LOGGING_NAMESPACE}
                    kubectl get pvc  -n ${LOGGING_NAMESPACE}
                '''
            }
        }

        stage('Deploy K3s') {
            steps {
                sh 'set -eux && kubectl apply -k k8s/app'
            }
        }

        stage('Rollout Restart') {
            steps {
                sh '''
                    set -eux
                    kubectl rollout restart deployment gateway-service -n gestion-projet
                    kubectl rollout status  deployment gateway-service -n gestion-projet --timeout=180s
                '''
            }
        }

        stage('Verify Logging') {
            steps {
                sh '''
                    set -eux
                    echo "⏳ Attente indexation Fluent Bit (20s)..."
                    sleep 20

                    OPENSEARCH_POD=$(kubectl get pod \
                        --namespace=${LOGGING_NAMESPACE} \
                        --selector=app=opensearch \
                        --output=jsonpath="{.items[0].metadata.name}")

                    echo "🔍 Indices OpenSearch :"
                    kubectl exec ${OPENSEARCH_POD} \
                        --namespace=${LOGGING_NAMESPACE} \
                        -- curl -s "http://localhost:9200/_cat/indices?v" || true

                    echo "💚 Santé du cluster OpenSearch :"
                    kubectl exec ${OPENSEARCH_POD} \
                        --namespace=${LOGGING_NAMESPACE} \
                        -- curl -s "http://localhost:9200/_cluster/health?pretty"

                    echo "🌐 Dashboards : http://<NODE_IP>:30601"
                '''
            }
        }
    }

    post {
        success {
            echo "✅ API-GATEWAY PIPELINE SUCCESS 🚀 — Dashboards: http://<NODE_IP>:30601"
        }

        failure {
            sh '''
                echo "=== Namespace gestion-projet ==="
                kubectl get pods      -n gestion-projet || true
                kubectl describe pods -n gestion-projet || true
                kubectl get events    -n gestion-projet || true

                echo "=== Namespace logging ==="
                kubectl get pods -n logging || true
                kubectl get pvc  -n logging || true

                kubectl describe deployment opensearch            -n logging || true
                kubectl describe deployment opensearch-dashboards -n logging || true
                kubectl describe daemonset  fluent-bit            -n logging || true

                echo "=== Logs OpenSearch ==="
                OPENSEARCH_POD=$(kubectl get pod \
                    --namespace=logging \
                    --selector=app=opensearch \
                    --output=jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "")
                if [ -n "$OPENSEARCH_POD" ]; then
                    kubectl logs ${OPENSEARCH_POD} --namespace=logging --tail=50 || true
                fi

                echo "=== Logs Fluent Bit ==="
                kubectl logs daemonset/fluent-bit --namespace=logging --tail=50 || true
            '''
        }

        always {
            cleanWs()
        }
    }
}