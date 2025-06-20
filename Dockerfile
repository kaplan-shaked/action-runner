FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy as build

ARG TARGETOS=linux
ARG TARGETARCH
ARG RUNNER_VERSION=2.325.0
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.7.0
ARG DOCKER_VERSION=28.2.1
ARG BUILDX_VERSION=0.24.0

RUN apt update -y && apt install curl unzip -y

WORKDIR /actions-runner
RUN export RUNNER_ARCH=${TARGETARCH} \
    && if [ "$RUNNER_ARCH" = "amd64" ]; then export RUNNER_ARCH=x64 ; fi \
    && curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${TARGETOS}-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz

RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip ./runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

RUN export RUNNER_ARCH=${TARGETARCH} \
    && if [ "$RUNNER_ARCH" = "amd64" ]; then export DOCKER_ARCH=x86_64 ; fi \
    && if [ "$RUNNER_ARCH" = "arm64" ]; then export DOCKER_ARCH=aarch64 ; fi \
    && curl -fLo docker.tgz https://download.docker.com/${TARGETOS}/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz \
    && tar zxvf docker.tgz \
    && rm -rf docker.tgz \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fLo /usr/local/lib/docker/cli-plugins/docker-buildx \
    "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-${TARGETARCH}" \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1

# 'gpg-agent' and 'software-properties-common' are needed for the 'add-apt-repository' command that follows
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
    sudo \
    && rm -rf /var/lib/apt/lists/*


RUN apt-get update && apt-get install -y \
    dphys-swapfile \
    && rm -rf /var/lib/apt/lists/*

# install cypress dependencies
RUN apt-get update && apt-get install libgtk2.0-0 libgtk-3-0 libgbm-dev libnotify-dev libnss3 libxss1 libasound2 libxtst6 xauth xvfb -y && rm -rf /var/lib/apt/lists/*

# apt-fast prerequisites
RUN apt-get update && apt-get install -y software-properties-common; rm -rf /var/lib/apt/lists/*
# Install apt-fast
RUN add-apt-repository ppa:apt-fast/stable
RUN apt-get update && apt-get install -y apt-fast
RUN echo "alias apt-get='apt-fast --no-install-recommends'" >> /root/.bashrc
RUN . /root/.bashrc

RUN apt-get install -y curl
RUN apt-get install -y unzip
RUN apt-get install -y zip
RUN apt-get install -y git
RUN apt-get install -y jq
RUN apt-get install libfreetype-dev -y
RUN apt-get install fontconfig -y
RUN apt-get install libsodium-dev -y
RUN apt-get install openjdk-17-jdk -y



RUN adduser --disabled-password --gecos "" --uid 1001 runner \
    && groupadd docker --gid 123 \
    && usermod -aG sudo runner \
    && usermod -aG docker runner \
    && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers \
    && echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers

WORKDIR /home/runner

COPY --chown=runner:docker --from=build /actions-runner .
COPY --from=build /usr/local/lib/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx

RUN install -o root -g root -m 755 docker/* /usr/bin/ && rm -rf docker

RUN apt-get install amazon-ecr-credential-helper -y

RUN curl -fsSL https://github.com/GoogleContainerTools/jib/releases/download/v0.13.0-cli/jib-jre-0.13.0.zip -o jib-cli.zip \
    && unzip jib-cli.zip \
    && rm jib-cli.zip \
    && ln -s /home/runner/jib-0.13.0/bin/jib /usr/local/bin/jib

# Install AWS-CLI
RUN apt-get install awscli -y

ARG NVM_VERSION=0.39.7
ARG NODE_VERSIONS="18 20 21"


# Switch back to runner user to install nvm
USER runner
SHELL ["/bin/bash", "--login", "-i", "-o", "pipefail", "-c"]
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash
RUN . $HOME/.bashrc
# # Install Node LTS
# RUN nvm install --lts
# RUN for version in $NODE_VERSIONS; do nvm install $version; done
# RUN nvm use --lts
