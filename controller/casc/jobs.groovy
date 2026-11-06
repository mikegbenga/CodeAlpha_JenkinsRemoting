// Job DSL — seeded by JCasC at controller start-up.
// Pipeline scripts live in controller/pipelines/ (copied into the image).

def pipelinesDir = '/usr/share/jenkins/pipelines'

folder('codealpha-remoting') {
    displayName('CodeAlpha · Jenkins Remoting')
    description('Demo jobs that run on remote agents connected through Jenkins Remoting.')
}

[
    [name: '01-multi-arch-build',
     file: 'multi-arch-build.groovy',
     desc: 'Compiles and runs the same program on x86_64 and arm64 agents at the same time, then gathers the artifacts.'],
    [name: '02-load-distribution',
     file: 'load-distribution.groovy',
     desc: 'Splits a workload into shards; the scheduler spreads them across every agent with the "linux" label.'],
    [name: '03-node-isolation-audit',
     file: 'node-isolation-audit.groovy',
     desc: 'Runs security checks on each agent: non-root user, no controller files, network segmentation.'],
    [name: '04-remote-machine-build',
     file: 'remote-machine-build.groovy',
     desc: 'Runs on remote-vm-01, a real machine connected with remote-node/install-agent.sh.'],
].each { j ->
    pipelineJob("codealpha-remoting/${j.name}") {
        description(j.desc)
        logRotator { numToKeep(20) }
        definition {
            cps {
                script(new File("${pipelinesDir}/${j.file}").text)
                sandbox(true)
            }
        }
    }
}
