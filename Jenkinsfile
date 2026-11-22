// Jenkins CI/CD pipeline for ACEest Fitness & Gym (Assignment 2).
//
// Checkout -> Install -> Lint -> Unit Tests + Coverage -> SonarQube ->
// Quality Gate -> Docker Build -> Test Inside Container -> Build Artifacts ->
// Push to Docker Hub -> Deploy to Kubernetes -> Verify (auto rollback on failure)
//
// The app version comes from the VERSION file. Change VERSION, commit, push:
// Jenkins (Poll SCM) builds and pushes <user>/aceest-fitness:<VERSION>.
pipeline {
    agent any

    parameters {
        choice(name: 'DEPLOY_STRATEGY',
               choices: ['rolling', 'blue-green', 'canary', 'ab-testing', 'shadow', 'all', 'none'],
               description: 'Deployment strategy. Automatic (Poll SCM) builds use the first one: rolling.')
        string(name: 'STABLE_VERSION', defaultValue: '',
               description: 'Optional. Current stable version (e.g. 2.2.4) for the FIRST setup of blue-green, canary, ab-testing or shadow.')
    }

    triggers {
        pollSCM('H/5 * * * *')
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
    }

    environment {
        DOCKERHUB_USER = 'CHANGE_ME'   // <-- put your Docker Hub username here
        IMAGE_NAME = "${DOCKERHUB_USER}/aceest-fitness"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.APP_VERSION = readFile('VERSION').trim()
                    env.IMAGE_TAG = "${env.APP_VERSION}-b${env.BUILD_NUMBER}"
                    env.STRATEGY = params.DEPLOY_STRATEGY ?: 'rolling'
                    env.STABLE_IMAGE = params.STABLE_VERSION ? "${env.IMAGE_NAME}:${params.STABLE_VERSION}" : ''
                    currentBuild.displayName = "#${env.BUILD_NUMBER} v${env.APP_VERSION} ${env.STRATEGY}"
                }
                echo "Version ${env.APP_VERSION}, image ${env.IMAGE_NAME}:${env.IMAGE_TAG}, strategy ${env.STRATEGY}"
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install --upgrade pip
                    pip install -r requirements.txt
                '''
            }
        }

        stage('Lint') {
            steps {
                sh '''
                    . venv/bin/activate
                    python -m py_compile app.py
                    flake8 app.py tests/
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    . venv/bin/activate
                    pytest -v --junitxml=test-results.xml \
                        --cov=app --cov-report=xml:coverage.xml --cov-report=term
                '''
            }
            post {
                always { junit 'test-results.xml' }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                script {
                    def scannerHome = tool name: 'SonarScanner',
                        type: 'hudson.plugins.sonar.SonarRunnerInstallation'
                    withSonarQubeEnv('sonarqube') {
                        sh "${scannerHome}/bin/sonar-scanner -Dsonar.projectVersion=${env.APP_VERSION}"
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                // SonarQube calls back Jenkins through its webhook; the build
                // fails here if the quality gate is red.
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    docker build \
                        --label org.opencontainers.image.version=$APP_VERSION \
                        --label org.opencontainers.image.revision=$GIT_COMMIT \
                        -t $IMAGE_NAME:$IMAGE_TAG \
                        -t $IMAGE_NAME:$APP_VERSION .
                '''
            }
        }

        stage('Test Inside Container') {
            steps {
                sh '''
                    # 1) the full Pytest suite inside the image
                    docker run --rm $IMAGE_NAME:$IMAGE_TAG pytest -v

                    # 2) start the real server (gunicorn) and smoke-test it
                    docker rm -f aceest-ci-$BUILD_NUMBER 2>/dev/null || true
                    docker run -d --name aceest-ci-$BUILD_NUMBER -p 127.0.0.1::5000 $IMAGE_NAME:$IMAGE_TAG
                    PORT=$(docker port aceest-ci-$BUILD_NUMBER 5000/tcp | head -1 | cut -d: -f2)
                    bash scripts/smoke_test.sh http://127.0.0.1:$PORT $APP_VERSION
                '''
            }
            post {
                always { sh 'docker rm -f aceest-ci-$BUILD_NUMBER 2>/dev/null || true' }
            }
        }

        stage('Build Artifacts') {
            steps {
                sh '''
                    mkdir -p dist
                    git archive --format=tar.gz --prefix=aceest-fitness-$APP_VERSION/ \
                        -o dist/aceest-fitness-$APP_VERSION-b$BUILD_NUMBER.tar.gz HEAD
                    {
                        echo "version=$APP_VERSION"
                        echo "build=$BUILD_NUMBER"
                        echo "commit=$GIT_COMMIT"
                        echo "image=$IMAGE_NAME:$IMAGE_TAG"
                        echo "image_version_tag=$IMAGE_NAME:$APP_VERSION"
                        echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
                    } > dist/build-info-$APP_VERSION-b$BUILD_NUMBER.txt
                    cp test-results.xml coverage.xml dist/
                '''
                archiveArtifacts artifacts: 'dist/*', fingerprint: true
            }
        }

        stage('Push to Docker Hub') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DH_USER',
                                                  passwordVariable: 'DH_TOKEN')]) {
                    sh '''
                        echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
                        docker push $IMAGE_NAME:$IMAGE_TAG
                        docker push $IMAGE_NAME:$APP_VERSION
                        docker tag $IMAGE_NAME:$IMAGE_TAG $IMAGE_NAME:latest
                        docker push $IMAGE_NAME:latest
                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to Kubernetes') {
            when { expression { env.STRATEGY != 'none' } }
            steps {
                // deploy.sh rolls back by itself if the new pods fail.
                sh 'bash scripts/deploy.sh $STRATEGY $IMAGE_NAME:$IMAGE_TAG $STABLE_IMAGE'
            }
        }

        stage('Verify Deployment') {
            when { expression { env.STRATEGY != 'none' } }
            steps {
                sh 'bash scripts/verify.sh $STRATEGY $APP_VERSION'
            }
            post {
                failure {
                    echo "Verification failed - rolling back ${env.STRATEGY}"
                    sh 'bash scripts/rollback.sh $STRATEGY'
                }
            }
        }
    }

    post {
        success {
            echo "SUCCESS: ${env.IMAGE_NAME}:${env.IMAGE_TAG} built, tested, pushed and deployed (${env.STRATEGY})"
        }
        failure {
            echo 'FAILED: check the stage logs above'
        }
        always {
            deleteDir()
        }
    }
}
