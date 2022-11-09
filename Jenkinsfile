pipeline {
    agent { label 'linux-amd64' }
    options {
        buildDiscarder(logRotator(daysToKeepStr: '30'))
    }
    triggers { cron(env.BRANCH_NAME ==~ /^main$/ ? 'H H(0-6) 1 * *' : '') }
    stages {
        stage('Build') {
            steps {
                sh 'docker buildx bake'
            }
        }
        stage('Publish') {
            environment {
                DOCKER_REGISTRY_CREDS = credentials('docker-registry-credentials')
            }
            when {
                branch 'main'
            }
            steps {
                sh 'echo "$DOCKER_REGISTRY_CREDS_PSW" | docker login --username "$DOCKER_REGISTRY_CREDS_USR" --password-stdin docker.io'
                sh 'docker buildx bake --push'
            }
            post {
                always {
                    sh 'docker logout docker.io'
                }
            }
        }
    }
}
