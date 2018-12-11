node {
    stage("Checkout") {
        checkout scm
    }
    stage("Build Docker Image") {
        sh "./gradlew test pushDockerImage"
    }
}
