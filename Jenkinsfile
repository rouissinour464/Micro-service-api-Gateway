pipeline {
    agent any

    triggers {
        cron('H/10 * * * *')
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
                sh './mvnw clean package -DskipTests'
            }
        }

        stage('Docker Build') {
            steps {
                sh "docker build -t ${IMAGE}:${TAG} ."
            }
        }

        stage('Docker Push') {
            steps {
                withCredentials([string(credentialsId: 'dockerhub-pass', variable: 'DOCKER_PASSWORD')]) {
                    sh "echo $DOCKER_PASSWORD | docker login -u ${REGISTRY} --password-stdin"
                    sh "docker push ${IMAGE}:${TAG}"
                }
            }
        }

        stage('Deploy to K3s (Kustomize)') {
            steps {
                sh '''
                    echo "Using kubeconfig: $KUBECONFIG"
                    kubectl apply -k k8s
                '''
            }
        }

        stage('Rollout Restart') {
            steps {
                sh '''
                    kubectl rollout restart deployment gateway-service -n gestion-projet
                '''
            }
        }
    }

    post {
        success {
            echo "✅ API-GATEWAY DEPLOYED SUCCESSFULLY 🎉"
        }
        failure {
            echo "❌ API-GATEWAY FAILED"
        }
    }
}
