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
        REGISTRY           = "nour292"
        IMAGE              = "${REGISTRY}/api-gateway"
        TAG                = "${BUILD_NUMBER}"
        KUBECONFIG         = "/var/lib/jenkins/.kube/config"
        NAMESPACE          = "gestion-projet"
        LOGGING_NS         = "logging"
        SONAR_PROJECT_KEY  = "rouissinour464_micro-service-api-gateway"
        SONAR_ORG          = "rouissinour464"
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
                    withCredentials([string(
                        credentialsId: 'sonar-token',
                        variable: 'SONAR_TOKEN'
                    )]) {
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
                    waitForQualityGate abortPipeline: false
                }
            }
        }

        stage('Docker Build & Push') {
            steps {
                withCredentials([string(
                    credentialsId: 'dockerhub-pass',
                    variable: 'DOCKER_PASSWORD'
                )]) {
                    sh '''
                        set -eux
                        docker build -t ${IMAGE}:${TAG} .
                        docker tag  ${IMAGE}:${TAG} ${IMAGE}:latest

                        echo "$DOCKER_PASSWORD" | \
                            docker login -u ${REGISTRY} --password-stdin
                        docker push ${IMAGE}:${TAG}
                        docker push ${IMAGE}:latest
                        docker logout

                        docker rmi ${IMAGE}:${TAG} ${IMAGE}:latest || true
                    '''
                }
            }
        }

        stage('Check Cluster') {
            steps {
                sh 'kubectl get nodes'
            }
        }

        // ─────────────────────────────────────────
        // Met à jour kustomization.yaml → git push
        // ArgoCD détecte et deploy automatiquement
        // ─────────────────────────────────────────
        stage('Update Git Tag') {
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

                        sed -i "/name: nour292\\/api-gateway/{n;s/newTag:.*/newTag: \\"${TAG}\\"/}" \
                            k8s/app/kustomization.yaml

                        git add k8s/app/kustomization.yaml
                        git diff --cached --quiet && \
                            echo "Pas de changement — skip" && exit 0

                        git commit -m "ci: api-gateway → ${TAG} [skip ci]"

                        REMOTE=$(git remote get-url origin \
                            | sed "s|https://|https://${GIT_USER}:${GIT_TOKEN}@|")
                        git push "$REMOTE" HEAD:v2 --force-with-lease
                    '''
                }
            }
        }

        // ─────────────────────────────────────────
        // Appliquer les ArgoCD Applications
        // UNE SEULE FOIS suffit — mais idempotent
        // enregistre front, gateway, user dans ArgoCD
        // ─────────────────────────────────────────
        stage('Apply ArgoCD Apps') {
            steps {
                sh '''
                    set -eux
                    kubectl apply -f k8s/argocd/ -n argocd
                    echo "ArgoCD apps enregistrées"
                '''
            }
        }

        // ─────────────────────────────────────────
        // ArgoCD sync automatique via Git
        // On attend juste que le deploy soit sain
        // ─────────────────────────────────────────
        stage('Wait ArgoCD Sync') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    sh '''
                        set -eux
                        echo "Attente sync ArgoCD (30s)..."
                        sleep 30

                        argocd app wait api-gateway \
                            --sync --health \
                            --timeout 240 \
                            --grpc-web || true

                        argocd app get api-gateway --grpc-web || true
                    '''
                }
            }
        }

        // ─────────────────────────────────────────
        // Logging — déployé seulement si absent
        // ─────────────────────────────────────────
        stage('Deploy Logging') {
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    sh '''
                        set -eux

                        OPENSEARCH_READY=$(kubectl get deployment opensearch \
                            -n ${LOGGING_NS} \
                            -o jsonpath='{.status.readyReplicas}' \
                            2>/dev/null || echo "0")
                        DASHBOARDS_READY=$(kubectl get deployment opensearch-dashboards \
                            -n ${LOGGING_NS} \
                            -o jsonpath='{.status.readyReplicas}' \
                            2>/dev/null || echo "0")

                        if [ "$OPENSEARCH_READY" -ge 1 ] && \
                           [ "$DASHBOARDS_READY" -ge 1 ]; then
                            echo "Logging deja UP — skip"
                            exit 0
                        fi

                        echo "Deploiement logging..."

                        kubectl create namespace ${LOGGING_NS} \
                            --dry-run=client -o yaml | kubectl apply -f -

                        kubectl create secret generic opensearch-credentials \
                            --from-literal=username="admin" \
                            --from-literal=password="admin" \
                            --namespace=${LOGGING_NS} \
                            --dry-run=client -o yaml | kubectl apply -f -

                        for PV in pv-opensearch-logs \
                                  pv-opensearch-dashboards \
                                  pv-fluentbit-db; do
                            STATUS=$(kubectl get pv $PV \
                                -o jsonpath='{.status.phase}' \
                                2>/dev/null || echo "NotFound")
                            if [ "$STATUS" = "Released" ]; then
                                kubectl patch pv $PV --type=json \
                                    -p='[{"op":"remove","path":"/spec/claimRef"}]' \
                                    || true
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
                    kubectl rollout status deployment/opensearch \
                        -n ${LOGGING_NS} --timeout=180s || true
                    kubectl rollout status deployment/opensearch-dashboards \
                        -n ${LOGGING_NS} --timeout=180s || true
                    echo "Logging stack OK"
                '''
            }
        }

        stage('Check Pods') {
            steps {
                sh '''
                    echo "=== Pods gestion-projet ==="
                    kubectl get pods -n ${NAMESPACE}

                    echo "=== Pods logging ==="
                    kubectl get pods -n ${LOGGING_NS}

                    echo "=== ArgoCD Apps ==="
                    kubectl get applications -n argocd || true
                '''
            }
        }
    }

    post {
        success {
            echo "SUCCES — api-gateway:${TAG} deploye"
        }
        failure {
            sh '''
                echo "=== Pods ==="
                kubectl get pods -n ${NAMESPACE} || true

                echo "=== Events ==="
                kubectl get events -n ${NAMESPACE} \
                    --sort-by=.lastTimestamp | tail -20 || true

                echo "=== ArgoCD ==="
                argocd app get api-gateway --grpc-web || true

                echo "=== Logs logging ==="
                kubectl logs -l app=opensearch \
                    -n logging --tail=50 || true
            '''
        }
        always { cleanWs() }
    }
}