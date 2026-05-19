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
                        sh 'set -eux && chmod +x mvnw && ./mvnw clean verify sonar:sonar -Dsonar.projectKey=${SONAR_PROJECT_KEY} -Dsonar.organization=${SONAR_ORG} -Dsonar.host.url=https://sonarcloud.io -Dsonar.token=${SONAR_TOKEN}'
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
                sh 'set -eux && kubectl get nodes'
            } 
        }

        stage('Deploy Logging Stack') {
            steps {
                sh '''
                    set -eux
                    echo "📦 Déploiement de la stack logging..."
                    kubectl apply -k k8s/logging
                    kubectl wait pod/opensearch --for=condition=Ready --namespace=${LOGGING_NAMESPACE} --timeout=180s
                    kubectl wait pod/opensearch-dashboards --for=condition=Ready --namespace=${LOGGING_NAMESPACE} --timeout=180s
                    kubectl rollout status daemonset/fluent-bit --namespace=${LOGGING_NAMESPACE} --timeout=120s
                    echo "✅ Stack logging déployée !"
                    kubectl get pods -n ${LOGGING_NAMESPACE}
                    kubectl get pvc   -n ${LOGGING_NAMESPACE}
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
                    kubectl rollout status deployment gateway-service -n gestion-projet --timeout=180s
                '''
            } 
        }

        stage('Verify Logging') {
            steps {
                sh '''
                    set -eux
                    echo "⏳ Attente Fluent Bit (20s)..."
                    sleep 20
                    kubectl exec pod/opensearch -n ${LOGGING_NAMESPACE} -- curl -s http://localhost:9200/_cat/indices?v || true
                    kubectl exec pod/opensearch -n ${LOGGING_NAMESPACE} -- curl -s "http://localhost:9200/_cluster/health?pretty"
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
                kubectl get pods    -n gestion-projet || true
                kubectl describe pods -n gestion-projet || true
                kubectl get events  -n gestion-projet || true
                echo "--- Logging Stack ---"
                kubectl get pods    -n logging || true
                kubectl get pvc     -n logging || true
                kubectl describe pod opensearch -n logging || true
            '''
        } 
 
        always { 
            cleanWs() 
        } 
    } 
}