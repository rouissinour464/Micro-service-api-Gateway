pipeline {
    agent any

    triggers {
        githubPush()
        cron('H */10 * * *')
    }

    options {
        timestamps()
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

    stages {

        /* ===================== */
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        /* ✅ BUILD + TEST + SONAR (FIX IMPORTANT) */
        stage('Build + Test + Sonar') {
            steps {
                withSonarQubeEnv('SonarCloud') {
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                        sh '''
                            set -eux
                            chmod +x mvnw

                            ./mvnw clean verify sonar:sonar \
                              -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                              -Dsonar.organization=${SONAR_ORG} \
                              -Dsonar.host.url=https://sonarcloud.io \
                              -Dsonar.token=${SONAR_TOKEN}
                        '''
                    }
                }
            }
        }

        /* ✅ QUALITY GATE */
        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        /* ✅ DOCKER */
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
                    kubectl get nodes
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
            echo "✅ API-GATEWAY PIPELINE SUCCESS 🚀"
        }

        failure {
            echo "❌ PIPELINE FAILED"

            sh '''
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