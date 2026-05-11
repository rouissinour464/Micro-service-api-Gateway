pipeline {
    agent any

    triggers {
        githubPush()
        cron('H */10 * * *')   // ⏱ toutes les 10 heures
    }

    tools {
        jdk 'JDK21'
    }

    environment {
        REGISTRY   = "nour292"
        IMAGE      = "${REGISTRY}/api-gateway"
        TAG        = "latest"
        KUBECONFIG = "/var/lib/jenkins/.kube/config"
        NAMESPACE  = "gestion-projet"
    }

    stages {

        /* ======================= */
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        /* ======================= */
        stage('Build') {
            steps {
                sh '''
                    set -eux
                    chmod +x mvnw
                    ./mvnw clean compile
                '''
            }
        }

        /* ======================= */
        stage('Unit Tests') {
            steps {
                sh '''
                    set -eux
                    ./mvnw test
                '''
            }
        }

        /* ======================= */
        stage('Integration Tests') {
            steps {
                sh '''
                    set -eux
                    ./mvnw verify
                '''
            }
        }

        /* ======================= */
        stage('Package JAR') {
            steps {
                sh '''
                    set -eux
                    ./mvnw package -DskipTests
                '''
            }
        }

        /* ======================= */
        stage('Docker Build') {
            steps {
                sh '''
                    set -eux
                    docker build -t ${IMAGE}:${TAG} .
                '''
            }
        }

        /* ======================= */
        stage('Docker Push') {
            steps {
                withCredentials([
                    string(credentialsId: 'dockerhub-pass', variable: 'DOCKER_PASSWORD')
                ]) {
                    sh '''
                        set -eux
                        echo "$DOCKER_PASSWORD" | docker login -u ${REGISTRY} --password-stdin
                        docker push ${IMAGE}:${TAG}
                        docker logout
                    '''
                }
            }
        }

        /* ======================= */
        stage('Deploy to K3s (Kustomize)') {
            steps {
                sh '''
                    set -eux
                    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                    kubectl apply -k ./k8s/app
                '''
            }
        }

        /* ======================= */
        stage('Update Image') {
            steps {
                sh '''
                    set -eux
                    kubectl set image deployment/gateway-service \
                    gateway-service=${IMAGE}:${TAG} \
                    -n ${NAMESPACE}
                '''
            }
        }

        /* ======================= */
        stage('Rollout Restart') {
            steps {
                sh '''
                    set -eux
                    kubectl rollout restart deployment gateway-service -n ${NAMESPACE}
                    kubectl rollout status deployment gateway-service -n ${NAMESPACE} --timeout=180s
                '''
            }
        }
    }

    post {
        success {
            echo "✅ API-GATEWAY BUILD + TESTS + DEPLOY SUCCESS ✅"
        }
        failure {
            echo "❌ PIPELINE STOPPED (TESTS / BUILD FAILURE)"
        }
        always {
            cleanWs()
        }
    }
}