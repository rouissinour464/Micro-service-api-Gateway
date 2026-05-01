pipeline {
    agent any

    triggers {
        githubPush()
        cron('H */10 * * *')   // ✅ toutes les 10 heures
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

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build JAR') {
            steps {
                sh '''
                    set -e
                    chmod +x mvnw
                    ./mvnw clean package -DskipTests
                '''
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    set -e
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
                        set -e
                        echo "$DOCKER_PASSWORD" | docker login -u ${REGISTRY} --password-stdin
                        docker push ${IMAGE}:${TAG}
                    '''
                }
            }
        }

        stage('Deploy to K3s (Kustomize)') {
            steps {
                sh '''
                    set -e
                    echo "Using kubeconfig: $KUBECONFIG"
                    kubectl apply -k k8s
                '''
            }
        }

        stage('Rollout Restart') {
            steps {
                sh '''
                    set -e
                    kubectl rollout restart deployment gateway-service -n gestion-projet
                    kubectl rollout status deployment gateway-service -n gestion-projet --timeout=180s
                '''
            }
        }
    }

    post {
        success {
            echo "✅ API-GATEWAY DEPLOYED SUCCESSFULLY 🎉"
        }
        failure {
            echo "❌ API-GATEWAY FAILED ❌"
        }
    }
}
