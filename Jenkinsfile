pipeline {
    agent any

    triggers {
        githubPush()
        cron('H */10 * * *')
    }

    tools {
        jdk 'JDK21'
    }

    environment {
        REGISTRY   = "nour292"
        IMAGE      = "${REGISTRY}/api-gateway"
        TAG        = "${BUILD_NUMBER}"
        KUBECONFIG = "/var/lib/jenkins/.kube/config"

        SONAR_PROJECT_KEY = "rouissinour464_micro-service-api-gateway"
        SONAR_ORG = "rouissinour464"
    }

    options {
        timestamps()
    }

    stages {

        /* ===================== */
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        /* ===================== */
        stage('Build + Test') {
            steps {
                sh '''
                    set -eux
                    chmod +x mvnw
                    ./mvnw clean verify
                '''
            }
        }

        /* ===================== */
        stage('SonarCloud') {
            steps {
                withSonarQubeEnv('SonarCloud') {
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                        sh '''
                            ./mvnw sonar:sonar \
                            -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                            -Dsonar.organization=${SONAR_ORG} \
                            -Dsonar.host.url=https://sonarcloud.io \
                            -Dsonar.login=${SONAR_TOKEN}
                        '''
                    }
                }
            }
        }

        /* ===================== */
        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        /* ===================== */
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

        /* ===================== */
        stage('Check Cluster Nodes') {
            steps {
                sh '''
                    set -eux

                    echo "=== CHECK NODES ==="
                    kubectl get nodes

                    # Vérifier si tous Ready
                    NOT_READY=$(kubectl get nodes --no-headers | grep -v " Ready" || true)

                    if [ ! -z "$NOT_READY" ]; then
                      echo "❌ Some nodes NOT READY"
                      kubectl get nodes
                      exit 1
                    fi

                    echo "✅ ALL NODES READY"
                '''
            }
        }

        /* ===================== */
        stage('Deploy K3s') {
            steps {
                sh '''
                    set -eux
                    kubectl apply -k k8s/app
                '''
            }
        }

        /* ===================== */
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
            echo "✅ API-GATEWAY FULL PIPELINE SUCCESS 🚀"
        }

        failure {
            echo "❌ PIPELINE FAILED"

            sh '''
                echo "=== DEBUG CLUSTER ==="
                kubectl get pods -n gestion-projet || true
                kubectl describe pods -n gestion-projet || true
                kubectl get events -n gestion-projet || true
            '''
        }

        always {
            cleanWs()
        }
    }
}
