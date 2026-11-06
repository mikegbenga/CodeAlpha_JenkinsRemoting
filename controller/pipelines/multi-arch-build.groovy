// Same source, compiled and executed on different CPU architectures in parallel
pipeline {
    agent none
    options {
        timestamps()
        timeout(time: 20, unit: 'MINUTES')
    }
    parameters {
        booleanParam(name: 'INCLUDE_ARM64', defaultValue: true, description: 'Run the arm64 leg (needs agent-linux-arm64 online)')
    }
    stages {
        stage('Build on every architecture') {
            parallel {
                stage('x86_64 (inbound WebSocket)') {
                    agent { label 'linux && amd64 && inbound' }
                    steps { buildAndRun('amd64') }
                }
                stage('arm64 (inbound WebSocket)') {
                    when { expression { params.INCLUDE_ARM64 } }
                    agent { label 'linux && arm64' }
                    steps { buildAndRun('arm64') }
                }
                stage('x86_64 (SSH, secure zone)') {
                    agent { label 'ssh && secure-zone' }
                    steps { buildAndRun('amd64-ssh') }
                }
            }
        }
        stage('Aggregate artifacts') {
            agent { label 'linux && amd64 && inbound' }
            steps {
                script {
                    def legs = ['amd64', 'amd64-ssh']
                    if (params.INCLUDE_ARM64) { legs << 'arm64' }
                    legs.each { leg -> unstash "bin-${leg}" }
                }
                sh '''
                    echo "=== Build matrix summary ==="
                    cat report-*.txt
                    tar czf multi-arch-bundle.tgz report-*.txt *.jar
                '''
                archiveArtifacts artifacts: 'multi-arch-bundle.tgz, report-*.txt', fingerprint: true
            }
            post { always { cleanWs() } }
        }
    }
}

def buildAndRun(String leg) {
    writeFile file: 'src/Hello.java', text: '''
public class Hello {
    public static void main(String[] a) {
        System.out.printf("Hello from %s | os.arch=%s | java=%s | cpus=%d%n",
            System.getenv().getOrDefault("NODE_NAME", "?"),
            System.getProperty("os.arch"),
            System.getProperty("java.version"),
            Runtime.getRuntime().availableProcessors());
    }
}'''
    sh """
        set -e
        echo "Node: \$NODE_NAME   Labels: \$NODE_LABELS"
        echo "Kernel: \$(uname -srm)"
        mkdir -p out
        javac -d out src/Hello.java
        jar cfe hello-${leg}.jar Hello -C out .
        java -jar hello-${leg}.jar | tee report-${leg}.txt
        echo "uname -m: \$(uname -m)" >> report-${leg}.txt
    """
    stash name: "bin-${leg}", includes: "hello-${leg}.jar, report-${leg}.txt"
    cleanWs()
}
