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

    environment {
        REGISTRY   = "nour292"
        IMAGE      = "${REGISTRY}/api-gateway"
        TAG        = "${BUILD_NUMBER}"
        KUBECONFIG = "/var/lib/jenkins/.kube/config"
        NAMESPACE  = "gestion-projet"
        LOGGING_NS = "logging"

        SONAR_PROJECT_KEY  = "rouissinour464_micro-service-api-gateway"
        SONAR_ORG          = "rouissinour464"

        GIT_CREDENTIALS_ID = "github-creds"
        GIT_USER_EMAIL     = "jenkins@ci.local"
        GIT_USER_NAME      = "Jenkins CI"
    }

    stages {

        // ============================================================
        stage('Checkout') {
        // ============================================================
            steps { checkout scm }
        }

        // ============================================================
        stage('Tests') {
        // ============================================================
            steps {
                sh '''
                    set -eux
                    chmod +x mvnw
                    echo "🧪 Lancement des tests d intégration..."
                    ./mvnw verify
                '''
            }
            post {
                always {
                    junit '**/target/surefire-reports/*.xml'
                }
            }
        }

        // ============================================================
        stage('SonarCloud Analysis') {
        // ============================================================
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

        // ============================================================
        stage('Quality Gate') {
        // ============================================================
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: false
                }
            }
        }

        // ============================================================
        stage('Docker Build & Push') {
        // ============================================================
            steps {
                withCredentials([string(credentialsId: 'dockerhub-pass', variable: 'DOCKER_PASSWORD')]) {
                    sh '''
                        set -eux

                        echo "🐳 Build image..."
                        docker build -t ${IMAGE}:${TAG} .
                        docker tag  ${IMAGE}:${TAG} ${IMAGE}:latest

                        echo "📤 Push image..."
                        echo "$DOCKER_PASSWORD" | docker login -u ${REGISTRY} --password-stdin
                        docker push ${IMAGE}:${TAG}
                        docker push ${IMAGE}:latest
                        docker logout

                        echo "🧹 Cleanup images locales..."
                        docker rmi ${IMAGE}:${TAG} ${IMAGE}:latest || true
                    '''
                }
            }
        }

        // ============================================================
        stage('Update Image Tag in Git') {
        // ============================================================
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
                        git diff --cached --quiet && echo "⏭️ Pas de changement — skip commit" && exit 0

                        git commit -m "ci: update api-gateway image tag to ${TAG} [skip ci]"

                        REMOTE=$(git remote get-url origin \
                            | sed "s|https://|https://${GIT_USER}:${GIT_TOKEN}@|")
                        git push "$REMOTE" HEAD:v2

                        echo "✅ Tag ${TAG} pushé sur branche v2"
                    '''
                }
            }
        }

        // ============================================================
        stage('Deploy via Kustomize') {
        // ============================================================
            steps {
                sh '''
                    set -eux

                    echo "📂 Contenu de k8s/app :"
                    ls -la k8s/app/

                    echo "🔍 Rendu Kustomize :"
                    kubectl kustomize k8s/app

                    echo "🏗️  Namespace..."
                    kubectl create namespace ${NAMESPACE} \
                        --dry-run=client -o yaml | kubectl apply -f -

                    echo "🚀 Apply Kustomize..."
                    kubectl apply -k k8s/app

                    echo "⏳ Attente Rollout..."
                    kubectl rollout status deployment/gateway-service \
                        -n ${NAMESPACE} --timeout=120s

                    echo "🔄 Restart forcé pour prendre la nouvelle image..."
                    kubectl rollout restart deployment/gateway-service \
                        -n ${NAMESPACE}

                    kubectl rollout status deployment/gateway-service \
                        -n ${NAMESPACE} --timeout=120s

                    echo "✅ api-gateway déployé"
                '''
            }
        }

        // ============================================================
        stage('ArgoCD Sync') {
        // ============================================================
            steps {
                sh '''
                    set -eux

                    echo "📋 Apply ArgoCD Application..."
                    kubectl apply -f k8s/argocd/ -n argocd

                    echo "🔄 Refresh ArgoCD repo server..."
                    kubectl rollout restart deployment argocd-repo-server -n argocd
                    kubectl rollout status deployment argocd-repo-server \
                        -n argocd --timeout=60s

                    echo "🔁 Force Sync ArgoCD..."
                    argocd app sync api-gateway --grpc-web || true

                    echo "⏳ Attente sync + health..."
                    argocd app wait api-gateway \
                        --sync --health --timeout 240 --grpc-web || true

                    echo "📊 Status ArgoCD..."
                    argocd app get api-gateway --grpc-web || true
                '''
            }
        }

        // ============================================================
        stage('Deploy Logging') {
        // ============================================================
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    sh '''
                        set -eux

                        # ── 0. Vérifier si logging déjà sain ─────────────────────
                        OPENSEARCH_READY=$(kubectl get deployment opensearch \
                            -n ${LOGGING_NS} \
                            -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
                        DASHBOARDS_READY=$(kubectl get deployment opensearch-dashboards \
                            -n ${LOGGING_NS} \
                            -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

                        echo "OpenSearch ready   : $OPENSEARCH_READY"
                        echo "Dashboards ready   : $DASHBOARDS_READY"

                        if [ "$OPENSEARCH_READY" -ge 1 ] && [ "$DASHBOARDS_READY" -ge 1 ]; then
                            echo "✅ Logging déjà UP — skip"
                            exit 0
                        fi

                        echo "⚙️  Logging absent/dégradé — déploiement..."

                        # ── 1. Namespace ──────────────────────────────────────────
                        kubectl create namespace ${LOGGING_NS} \
                            --dry-run=client -o yaml | kubectl apply -f -

                        # ── 2. Secret OpenSearch ──────────────────────────────────
                        kubectl create secret generic opensearch-credentials \
                            --from-literal=username="admin" \
                            --from-literal=password="admin" \
                            --namespace=${LOGGING_NS} \
                            --dry-run=client -o yaml | kubectl apply -f -

                        # ── 3. Libérer PVs Released ───────────────────────────────
                        for PV in pv-opensearch-logs pv-opensearch-dashboards pv-fluentbit-db; do
                            STATUS=$(kubectl get pv $PV \
                                -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
                            echo "PV $PV : $STATUS"
                            if [ "$STATUS" = "Released" ]; then
                                kubectl patch pv $PV --type=json \
                                    -p='[{"op":"remove","path":"/spec/claimRef"}]' || true
                            fi
                        done

                        # ── 4. Vérification PVCs ──────────────────────────────────
                        check_and_fix_pvc() {
                            PVC_NAME=$1
                            LABEL_VAL=$2
                            NS=${LOGGING_NS}

                            if [ "$PVC_NAME" = "pvc-opensearch-dashboards" ]; then
                                echo "🔒 $PVC_NAME : protégé — skip"
                                return
                            fi

                            EXISTS=$(kubectl get pvc "$PVC_NAME" -n "$NS" \
                                --ignore-not-found \
                                -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")

                            if [ -z "$EXISTS" ]; then
                                echo "✅ $PVC_NAME : absent → sera créé"
                                return
                            fi

                            CURRENT=$(kubectl get pvc "$PVC_NAME" -n "$NS" -o json 2>/dev/null \
                                | python3 -c "
import sys, json
data = json.load(sys.stdin)
labels = data.get('spec',{}).get('selector',{}).get('matchLabels',{})
print(labels.get('volume-for',''))
" 2>/dev/null || echo "")

                            echo "$PVC_NAME : selector='$CURRENT' attendu='$LABEL_VAL'"

                            if [ "$CURRENT" != "$LABEL_VAL" ]; then
                                echo "⚠️  Selector incorrect → recréation $PVC_NAME"
                                kubectl delete pvc "$PVC_NAME" -n "$NS" --ignore-not-found=true
                                kubectl wait --for=delete "pvc/$PVC_NAME" \
                                    -n "$NS" --timeout=60s || true

                                PV_NAME="pv-$(echo $PVC_NAME | sed 's/^pvc-//')"
                                PV_ST=$(kubectl get pv "$PV_NAME" \
                                    -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
                                if [ "$PV_ST" = "Released" ]; then
                                    kubectl patch pv "$PV_NAME" --type=json \
                                        -p='[{"op":"remove","path":"/spec/claimRef"}]' || true
                                fi
                            fi
                        }

                        check_and_fix_pvc "pvc-opensearch-logs"      "opensearch-logs"
                        check_and_fix_pvc "pvc-opensearch-dashboards" "opensearch-dashboards"
                        check_and_fix_pvc "pvc-fluentbit-db"          "fluentbit-db"

                        # ── 5. Apply PVs + PVCs ───────────────────────────────────
                        kubectl apply -f k8s/logging/pv-pvc.yaml

                        # ── 6. Apply stack logging ────────────────────────────────
                        kubectl apply -k k8s/logging

                        echo "✅ Logging déployé"
                    '''
                }
            }
        }

        // ============================================================
        stage('Wait Logging Ready') {
        // ============================================================
            steps {
                sh '''
                    set -eux
                    kubectl rollout status deployment/opensearch \
                        -n ${LOGGING_NS} --timeout=180s || true
                    kubectl rollout status deployment/opensearch-dashboards \
                        -n ${LOGGING_NS} --timeout=180s || true
                    echo "✅ Logging stack prêt"
                '''
            }
        }

        // ============================================================
        stage('Check Pods') {
        // ============================================================
            steps {
                sh '''
                    set -eux

                    echo "📦 Pods gestion-projet :"
                    kubectl get pods -n ${NAMESPACE}

                    echo "📦 Pods logging :"
                    kubectl get pods -n ${LOGGING_NS}

                    echo "💾 PVCs logging :"
                    kubectl get pvc -n ${LOGGING_NS}

                    echo "💾 PVs logging :"
                    kubectl get pv | grep logging-local || true

                    echo "🚀 Deployments :"
                    kubectl get deployments -n ${NAMESPACE}
                '''
            }
        }

        // ============================================================
        stage('Check Logs Pipeline') {
        // ============================================================
            steps {
                sh '''
                    set -eux

                    kubectl run log-test \
                        --image=busybox --restart=Never \
                        -- echo "hello logs" || true
                    sleep 5

                    kubectl port-forward \
                        -n ${LOGGING_NS} svc/opensearch 9200:9200 \
                        > /dev/null 2>&1 &
                    PF_PID=$!
                    sleep 5

                    curl -s localhost:9200/_cat/indices?v || true

                    kubectl delete pod log-test --ignore-not-found=true
                    kill $PF_PID || pkill -f "port-forward.*9200" || true
                '''
            }
        }

    } // end stages

    post {
        success {
            echo "✅ PIPELINE SUCCESS — api-gateway:${TAG} déployé 🚀"
        }
        failure {
            echo "❌ PIPELINE FAILED"
            sh '''
                echo "=== Pods ==="
                kubectl get pods -A || true

                echo "=== Logs gateway ==="
                kubectl logs -l app=gateway-service \
                    -n ${NAMESPACE} --tail=50 || true

                echo "=== Logs OpenSearch ==="
                kubectl logs -l app=opensearch \
                    -n logging --tail=50 || true

                echo "=== Logs Dashboards ==="
                kubectl logs -l app=opensearch-dashboards \
                    -n logging --tail=50 || true

                echo "=== Logs FluentBit ==="
                kubectl logs -l app=fluent-bit \
                    -n logging --tail=50 || true

                echo "=== ArgoCD status ==="
                argocd app get api-gateway --grpc-web || true
            '''
        }
        always {
            cleanWs()
        }
    }
}