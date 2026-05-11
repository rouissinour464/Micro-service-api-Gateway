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
    }

    stages {

        /* =======================
           SOURCE
        ======================= */
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        /* =======================
           BUILD (sans tests)
        ======================= */
        stage('Build') {
            steps {
                sh '''
                    set -eux
                    chmod +x mvnw
                    ./mvnw clean compile
                '''
            }
        }

        /* =======================
           TESTS UNITAIRES
        ======================= */
        stage('Unit Tests') {
            steps {
                sh '''
                    set -eux
                    ./mvnw test
                '''
            }
        }

        /* =======================
           TESTS D’INTÉGRATION
        ======================= */
        stage('Integration Tests') {
            steps {
                sh '''
                    set -eux
                    ./mvnw verify
                '''
            }
        }

        /* =======================
           PACKAGE JAR
        ======================= */
        stage('Package JAR') {
            steps {
                sh '''
                    set -eux
                    ./mvnw package -DskipTests
                '''
            }
        }

        /* =======================
           DOCKER
        ======================= */
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
                withCredentials([
                    string(credentialsId: 'dockerhub-pass', variable: 'DOCKER_PASSWORD')
                ]) {
                    sh '''
                        set -eux
                        echo "$DOCKER_PASSWORD" | docker login -u ${REGISTRY} --password-stdin
                        docker push ${IMAGE}:${TAG}
                    '''
                }
            }
        }

        /* =======================
           DEPLOY K3s
        ======================= */
        stage('Deploy to K3s (Kustomize)') {
            steps {
                sh '''
                    set -eux
                    kubectl apply -k k8s
                '''
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
    }

    post {
        success {
            echo "✅ API‑GATEWAY BUILD + TESTS + DEPLOY SUCCESS ✅"
        }
        failure {
            echo "❌ PIPELINE STOPPED (TESTS / BUILD FAILURE)"
        }
        always {
            cleanWs()
        }
    }
}