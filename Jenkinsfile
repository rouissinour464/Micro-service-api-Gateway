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
           CHECKOUT SOURCE
        ======================= */
        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    set -eux
                    pwd
                    ls -R
                '''
            }
        }

        /* =======================
           BUILD
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
           UNIT TESTS
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
           INTEGRATION TESTS
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
           DOCKER BUILD
        ======================= */
        stage('Docker Build') {
            steps {
                sh '''
                    set -eux
                    docker build -t ${IMAGE}:${TAG} .
                '''
            }
        }

        /* =======================
           DOCKER PUSH
        ======================= */
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

        /* =======================
           VERIFY K8S FILES
        ======================= */
        stage('Verify K8s Files') {
            steps {
                sh '''
                    set -eux

                    ls -R k8s

                    test -f k8s/app/gateway-deployment.yml
                    test -f k8s/app/gateway-service.yml
                    test -f k8s/app/kustomization.yaml
                '''
            }
        }

        /* =======================
           DEPLOY K3s
        ======================= */
        stage('Deploy to K3s (Kustomize)') {
            steps {
                sh '''
                    set -eux

                    kubectl apply -k k8s/app
                '''
            }
        }

        /* =======================
           ROLLOUT RESTART
        ======================= */
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