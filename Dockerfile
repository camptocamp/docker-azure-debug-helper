FROM debian:buster

LABEL maintainer="georchestra@camptocamp.com"

ENV GOVERSION="1.15" \
    GOPATH="/go" \
    GOROOT="/goroot" \
    GO111MODULE=on \
    TOOLS="openssh-server groff awscli rsync vim-nox emacs-nox screen gdal-bin pktools wget file python-gdal nano htop sudo tree less bash-completion zsh figlet colordiff unzip python3 python3-pip" \
    DOCKER_KEY="https://download.docker.com/linux/debian/gpg" \
    DOCKER_REPO="deb [arch=amd64] https://download.docker.com/linux/debian buster stable" \
    DOCKER_PACKAGE="docker-ce-cli" \
    PGDG_KEY="https://www.postgresql.org/media/keys/ACCC4CF8.asc" \
    PGDG_REPO="deb http://apt.postgresql.org/pub/repos/apt/ buster-pgdg main" \
    PGDG_PACKAGE="postgresql-client-9.2 postgresql-client-9.3 postgresql-client-9.4 postgresql-client-9.5 postgresql-client-9.6 postgresql-client-10 postgresql-client-11  postgresql-client-12 libpq-dev" \
    AZURE_KEY="https://packages.microsoft.com/keys/microsoft.asc" \
    AZURE_REPO="deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ buster main" \
    AZURE_PACKAGE="azure-cli"

# Use bash to build image for dynamic variables substitution
SHELL ["/bin/bash", "-c"]

# Install basic apt tools and install Golang
RUN apt-get update \
    && apt-get -y install git curl ca-certificates gnupg apt-transport-https \
    && if [ -z "${HTTP_PROXY}" ] ; then git config --global http.proxy ${HTTP_PROXY} ; else echo No proxy configured ; fi || true \
    && curl https://storage.googleapis.com/golang/go${GOVERSION}.linux-amd64.tar.gz | tar xzf - \
    && mv ${GOPATH} ${GOROOT} \
    && ${GOROOT}/bin/go get github.com/camptocamp/github_pki \
    && rm -rf go${GOVERSION}.linux-amd64.tar.gz ${GOROOT} \
    && apt-get clean && \
    rm -rf /var/apt/lists/*


# Install keys for external repository
RUN for key in "${DOCKER_KEY} ${PGDG_KEY} ${AZURE_KEY}"; do \
      curl -fsSL $key | apt-key add - ;\
    done && \
    for key in DOCKER_REPO PGDG_REPO AZURE_REPO; do \
      echo ${!key} >> /etc/apt/sources.list ;\
    done  && \
    apt-get update && \
    apt-get install -y ${DOCKER_PACKAGE} ${PGDG_PACKAGE} ${AZURE_PACKAGE} && \
    apt-get install -y ${TOOLS} && \
    apt-get clean && \
    rm -rf /var/apt/lists/*


# docker-cli 45/188
# pg-cli 10/46


# Install some python tools
RUN pip3 install --no-cache-dir pgcli Flask paramiko

# Configure openssh-server
RUN rm -f /etc/ssh/ssh_host_*_key* \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir /var/run/sshd /etc/ssh/ssh_host_keys \
  && sed -i -e 's@#HostKey /etc/ssh/ssh_host@HostKey /etc/ssh/ssh_host_keys/ssh_host@g' /etc/ssh/sshd_config \
  && echo "AllowUsers sftp" >> /etc/ssh/sshd_config \
  && echo "PasswordAuthentication no" >> /etc/ssh/sshd_config \
  && cp /etc/ssh/sshd_config /etc/ssh/sshd_config.client \
  && sed -i -e 's@^Subsystem sftp .*@Subsystem sftp internal-sftp@' /etc/ssh/sshd_config.client \
  && echo "Match User sftp" >> /etc/ssh/sshd_config.client \
  && echo "    AllowTcpForwarding no" >> /etc/ssh/sshd_config.client \
  && echo "    X11Forwarding no" >> /etc/ssh/sshd_config.client \
  && echo "    ForceCommand internal-sftp" >> /etc/ssh/sshd_config.client

# Add helper scripts
ADD script/* /usr/local/bin/
ADD script_completion /etc/bash_completion.d/

# Setup sudo
RUN echo "%sudo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sudo-group

# Configure ssh user
RUN useradd -r -d /home/sftp --shell /bin/bash sftp \
  && mkdir -p /home/sftp.skel/.ssh \
  && chown -R sftp.sftp /home/sftp.skel \
  && ln -s /mnt /home/sftp.skel/data

RUN addgroup sftp sudo

# Configure some alias and add big env message with figlet at startup
ADD bash_profile /home/sftp.skel/.bash_profile
RUN chown sftp /home/sftp.skel/.bash_profile

# Define VOLUMES
VOLUME ["/etc/ssh/ssh_host_keys", "/home/sftp"]

# Configure entrypoint and command
COPY docker-entrypoint.sh /
COPY docker-entrypoint.d /docker-entrypoint.d
ADD docker-entrypoint.py /docker-entrypoint.py

ENV GITHUB_USERS ""
EXPOSE 5000 22
ENTRYPOINT ["/docker-entrypoint.sh", "/usr/sbin/sshd", "-D", "-e"]
