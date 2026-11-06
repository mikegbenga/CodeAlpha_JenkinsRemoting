# Jenkins controller, configured entirely as code (JCasC + Job DSL).
FROM jenkins/jenkins:lts-jdk17

# Skip the interactive setup wizard: security comes from casc/jenkins.yaml
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    CASC_JENKINS_CONFIG=/usr/share/jenkins/casc

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --verbose

COPY --chown=jenkins:jenkins casc/      /usr/share/jenkins/casc/
COPY --chown=jenkins:jenkins pipelines/ /usr/share/jenkins/pipelines/

HEALTHCHECK --interval=20s --timeout=5s --start-period=90s --retries=5 \
  CMD ["curl", "-fsS", "-o", "/dev/null", "http://localhost:8080/login"]
