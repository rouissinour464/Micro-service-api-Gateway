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

                        git checkout -B v2

                        # ✅ Mise à jour ciblée (évite casser autres images)
                        sed -i "/name: nour292\\/api-gateway/{n;s/newTag:.*/newTag: \\"${TAG}\\"/}" k8s/app/kustomization.yaml

                        git add k8s/app/kustomization.yaml
                        git commit -m "ci: update api-gateway image tag to ${TAG} [skip ci]" || true

                        REMOTE=$(git remote get-url origin | sed "s|https://|https://${GIT_USER}:${GIT_TOKEN}@|")
                        git push "$REMOTE" HEAD:v2
                    '''
                }
            }
        }

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

        stage('Refresh ArgoCD Cache') {
            steps {
                sh '''
                    set -eux
                    kubectl rollout restart deployment argocd-repo-server -n argocd
                '''
            }
        }

        stage('Force Sync ArgoCD') {
            steps {
                sh '''
                    set -eux
                    argocd app sync api-gateway --grpc-web || true
                '''
            }
        }

        stage('Debug Kustomize') {
            steps {
                sh '''
                    set -eux
                    echo "🔍 Debug Kustomize"
                    kustomize build k8s/app || true
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

                        echo "🔧 Fix PVs..."
                        for PV in pv-opensearch-logs pv-opensearch-dashboards pv-fluentbit-db; do
                            STATUS=$(kubectl get pv $PV -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
                            if [ "$STATUS" = "Released" ]; then
                                kubectl patch pv $PV --type=json \
                                    -p='[{"op":"remove","path":"/spec/claimRef"}]' || true
                            fi
                        done

                        kubectl apply -f k8s/logging/pv-pvc.yaml
                        kubectl apply -k k8s/logging
                    '''
                }
            }
        }

        stage('Wait Logging Ready') {
            steps {
                sh '''
                    set -eux
                    kubectl rollout status deployment/opensearch -n ${LOGGING_NS} --timeout=120s || true
                    kubectl rollout status deployment/opensearch-dashboards -n ${LOGGING_NS} --timeout=120s || true
                '''
            }
        }

        stage('Check Pods') {
            steps {
                sh '''
                    set -eux
                    kubectl get pods -n ${NAMESPACE}
                    kubectl get pods -n ${LOGGING_NS}
                    kubectl get pvc -n ${LOGGING_NS}
                    kubectl get pv | grep logging-local || true
                '''
            }
        }

        stage('Check Logs Pipeline') {
            steps {
                sh '''
                    set -eux
                    kubectl run log-test --image=busybox --restart=Never -- echo "hello logs" || true
                    sleep 5

                    kubectl port-forward -n ${LOGGING_NS} svc/opensearch 9200:9200 > /dev/null 2>&1 &
                    sleep 5

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