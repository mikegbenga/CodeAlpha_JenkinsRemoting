// Fan-out a workload into shards; Jenkins' scheduler spreads them across all
// agents that carry the requested label, so the build load is shared.
pipeline {
    agent none
    options { timestamps() }
    parameters {
        string(name: 'SHARDS', defaultValue: '6', description: 'Number of parallel shards')
        string(name: 'WORK_SECONDS', defaultValue: '20', description: 'Simulated work per shard')
        string(name: 'AGENT_LABEL', defaultValue: 'linux', description: 'Label expression shards may run on')
    }
    stages {
        stage('Distribute') {
            steps {
                script {
                    int shards = params.SHARDS as int
                    def branches = [:]
                    for (int i = 1; i <= shards; i++) {
                        def n = i
                        branches["shard-${n}"] = {
                            node(params.AGENT_LABEL) {
                                sh """
                                    START=\$(date +%s)
                                    echo "shard-${n} -> \$NODE_NAME (\$(uname -m)) executor \$EXECUTOR_NUMBER"
                                    # simulated CPU work
                                    timeout ${params.WORK_SECONDS} sh -c 'while :; do :; done' || true
                                    echo "shard-${n},\$NODE_NAME,\$(uname -m),\$(( \$(date +%s) - START ))s" > shard-${n}.csv
                                """
                                stash name: "shard-${n}", includes: "shard-${n}.csv"
                                cleanWs()
                            }
                        }
                    }
                    parallel branches
                }
            }
        }
        stage('Report') {
            agent { label 'linux && amd64 && inbound' }
            steps {
                script {
                    for (int i = 1; i <= (params.SHARDS as int); i++) { unstash "shard-${i}" }
                }
                sh '''
                    echo "shard,node,arch,duration" > distribution.csv
                    cat shard-*.csv >> distribution.csv
                    column -s, -t distribution.csv || cat distribution.csv
                    echo
                    echo "Shards per node:"
                    tail -n +2 distribution.csv | cut -d, -f2 | sort | uniq -c
                '''
                archiveArtifacts 'distribution.csv'
            }
            post { always { cleanWs() } }
        }
    }
}
