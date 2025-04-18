FROM ubuntu:24.04

ENV MONERO_HASH 51ba03928d189c1c11b5379cab17dd9ae8d2230056dc05c872d0f8dba4a87f1d
ENV MONERO_DL_URL https://downloads.getmonero.org/cli/monero-linux-x64-v0.18.3.4.tar.bz2
ENV MONERO_DL_FILE monero.tar.bz2
ENV MONERO_SUMS_FILE sha256sums

WORKDIR /opt/monero

# Update system and install dependencies
# Download Monero binaries from getmonero.org
# Confirm hashes match
# Install daemon binary
# Clean up

RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y tar wget bzip2

RUN wget -qO ${MONERO_DL_FILE} ${MONERO_DL_URL} \
  && echo "${MONERO_HASH}  ${MONERO_DL_FILE}" > ${MONERO_SUMS_FILE} \
  && sha256sum -c ${MONERO_SUMS_FILE}; \
  if [ "$?" -eq 0 ]; \
  then \
    echo -e "[+] Hashes match - proceeding with container build"; \
  else \
    echo -e "[!] Hashes do not match - exiting"; \
    exit 5; \
  fi \
  && mkdir ./tmp \
  && tar xjf ${MONERO_DL_FILE} -C ./tmp --strip 1 \
  && mv ./tmp/* /usr/local/bin/ \
  && rm -rf ./tmp ${MONERO_SUMS_FILE} ${MONERO_DL_FILE}

WORKDIR /data

RUN wget https://gui.xmr.pm/files/block.txt -q

EXPOSE 18080
EXPOSE 18081
EXPOSE 18082
EXPOSE 18083
