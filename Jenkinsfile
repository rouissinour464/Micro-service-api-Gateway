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

                        echo "$DOCKER_PASSWORD" | docker login -u ${REGISTRY} --password-stdin

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

                    echo "📦 Create namespace logging"
                    kubectl create namespace ${LOGGING_NAMESPACE} \
                        --dry-run=client -o yaml | kubectl apply -f -

                    echo "🚀 Apply logging stack (kustomize)"
                    kubectl apply -k k8s/logging

                    echo "⏳ Wait OpenSearch..."
                    kubectl rollout status deployment/opensearch \
                        -n ${LOGGING_NAMESPACE} \
                        --timeout=600s

                    echo "⏳ Wait OpenSearch Dashboards..."
                    kubectl rollout status deployment/opensearch-dashboards \
                        -n ${LOGGING_NAMESPACE} \
                        --timeout=600s

                    echo "⏳ Wait Fluent Bit..."
                    kubectl rollout status daemonset/fluent-bit \
                        -n ${LOGGING_NAMESPACE} \
                        --timeout=180s

                    echo "✅ Logging stack ready"

                    kubectl get pods -n ${LOGGING_NAMESPACE}
                '''
            }
        }

        stage('Deploy Application') {
            steps {
                sh '''
                    set -eux

                    echo "📦 Create namespace app"
                    kubectl create namespace ${APP_NAMESPACE} \
                        --dry-run=client -o yaml | kubectl apply -f -

                    echo "🚀 Deploy application"
                    kubectl apply -k k8s/app
                '''
            }
        }

        stage('Rollout Restart') {
            steps {
                sh '''
                    set -eux

                    kubectl rollout restart deployment gateway-service -n ${APP_NAMESPACE}
                    kubectl rollout status deployment gateway-service -n ${APP_NAMESPACE} --timeout=300s
                '''
            }
        }

        stage('Verify Logging') {
            steps {
                sh '''
                    set -eux

                    echo "⏳ Wait indexing..."
                    sleep 20

                    OPENSEARCH_POD=$(kubectl get pod \
                        -n ${LOGGING_NAMESPACE} \
                        -l app=opensearch \
                        -o jsonpath="{.items[0].metadata.name}")

                    echo "📊 Cluster health"
                    kubectl exec $OPENSEARCH_POD -n ${LOGGING_NAMESPACE} -- \
                        curl -s http://localhost:9200/_cluster/health?pretty

                    echo "📚 Indices"
                    kubectl exec $OPENSEARCH_POD -n ${LOGGING_NAMESPACE} -- \
                        curl -s http://localhost:9200/_cat/indices?v

                    echo "🌐 Dashboards URL"
                    echo "http://<NODE_IP>:30601"
                '''
            }
        }
    }

    post {
        success {
            echo """
✅ SUCCESS PIPELINE

🌐 OpenSearch Dashboards:
http://<NODE_IP>:30601
"""
        }

        failure {
            sh '''
                echo "❌ FAILURE LOGS"

                echo "APP PODS"
                kubectl get pods -n ${APP_NAMESPACE} || true

                echo "LOGGING PODS"
                kubectl get pods -n ${LOGGING_NAMESPACE} || true

                echo "OPENSEARCH LOGS"
                kubectl logs -n ${LOGGING_NAMESPACE} -l app=opensearch --tail=100 || true

                echo "DASHBOARDS LOGS"
                kubectl logs -n ${LOGGING_NAMESPACE} -l app=opensearch-dashboards --tail=100 || true
            '''
        }

        always {
            cleanWs()
        }
    }
}