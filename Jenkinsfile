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

        GIT_CREDENTIALS_ID = "github-creds"
        GIT_USER_EMAIL     = "jenkins@ci.local"
        GIT_USER_NAME      = "Jenkins CI"
    }

    stages {

        stage('Checkout') {
            steps { checkout scm }
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

        stage('Update Image Tag') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${GIT_CREDENTIALS_ID}",
                    usernameVariable: 'GIT_USER',
                    passwordVariable: 'GIT_TOKEN'
                )]) {
                    sh '''
                        set -eux
                        git config user.email "${GIT_USER_EMAIL}"
                        git config user.name  "${GIT_USER_NAME}"

                        sed -i "s|newTag:.*|newTag: \\"${TAG}\\"|g" k8s/app/kustomization.yaml

                        git add k8s/app/kustomization.yaml
                        git commit -m "ci: update api-gateway image tag to ${TAG} [skip ci]"

                        REMOTE=$(git remote get-url origin \
                            | sed "s|https://|https://${GIT_USER}:${GIT_TOKEN}@|")
                        git push "$REMOTE" HEAD:$(git rev-parse --abbrev-ref HEAD)
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────
        // NOUVEAU : applique tous les fichiers ArgoCD
        // app-gateway, app-user, app-stage, app-frontend
        // ─────────────────────────────────────────────
        stage('Apply ArgoCD Apps') {
            steps {
                sh '''
                    set -eux
                    kubectl apply -f k8s/argocd/ -n argocd
                    echo "✅ ArgoCD apps applied"
                    argocd app list --grpc-web || true
                '''
            }
        }

        stage('Wait ArgoCD Sync') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    sh '''
                        set -eux
                        argocd app wait api-gateway \
                            --sync --health --timeout 240 --grpc-web || true
                        argocd app get api-gateway --grpc-web || true
                    '''
                }
            }
        }

        stage('Deploy Logging') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    sh '''
                        set -eux

                        kubectl create namespace ${LOGGING_NS} \
                            --dry-run=client -o yaml | kubectl apply -f -

                        echo "🔧 Vérification et fix des PVs..."
                        for PV in pv-opensearch-logs pv-opensearch-dashboards pv-fluentbit-db; do
                            STATUS=$(kubectl get pv $PV -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
                            echo "PV $PV → $STATUS"
                            if [ "$STATUS" = "Released" ]; then
                                kubectl patch pv $PV --type=json \
                                    -p='[{"op":"remove","path":"/spec/claimRef"}]' || true
                                echo "✅ PV $PV libéré"
                            fi
                        done

                        kubectl apply -f k8s/logging/pv-pvc.yaml

                        echo "⏳ Attente PVs Available..."
                        for i in $(seq 1 10); do
                            ALL_OK=true
                            for PV in pv-opensearch-logs pv-opensearch-dashboards pv-fluentbit-db; do
                                STATUS=$(kubectl get pv $PV -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
                                if [ "$STATUS" != "Available" ] && [ "$STATUS" != "Bound" ]; then
                                    ALL_OK=false
                                fi
                            done
                            if [ "$ALL_OK" = "true" ]; then
                                echo "✅ Tous les PVs sont prêts"
                                break
                            fi
                            echo "Tentative $i/10 — attente 3s..."
                            sleep 3
                        done

                        kubectl apply -k k8s/logging
                    '''
                }
            }
        }

        stage('Wait Logging Ready') {
            steps {
                sh '''
                    set -eux
                    echo "⏳ OpenSearch check (120s max)"
                    kubectl rollout status deployment/opensearch \
                        -n ${LOGGING_NS} --timeout=120s || true

                    echo "⏳ Dashboards check (120s max)"
                    kubectl rollout status deployment/opensearch-dashboards \
                        -n ${LOGGING_NS} --timeout=120s || true
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
