// Runs on a real machine elsewhere on the network (remote-vm-01), connected
// with remote-node/install-agent.sh. Proves Remoting works beyond Docker.
pipeline {
    agent { label 'remote && bare-metal' }
    options {
        timestamps()
        timeout(time: 10, unit: 'MINUTES')
    }
    stages {
        stage('Host facts') {
            steps {
                sh '''
                    echo "Agent:    $NODE_NAME"
                    echo "Host:     $(hostname)"
                    echo "OS:       $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -s)"
                    echo "Arch:     $(uname -m)"
                    echo "CPUs:     $(nproc)"
                    echo "Memory:   $(free -h 2>/dev/null | awk '/Mem:/{print $2}')"
                    echo "User:     $(id -un)"
                    echo "Workdir:  $WORKSPACE"
                    java -version 2>&1 | head -1
                '''
            }
        }
        stage('Build') {
            steps {
                writeFile file: 'build-info.txt', text: "Built on ${env.NODE_NAME} at ${new Date()}\n"
                archiveArtifacts 'build-info.txt'
            }
        }
    }
    post { always { cleanWs() } }
}
