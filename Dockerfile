FROM golang:1.22.3 as MEMORY_CALCULATOR
RUN mkdir -p /build-temp/src
WORKDIR /build-temp/src

# CGO_ENABLED=0 forces go to use native go implementations instead of calling C
# where possible. The end result is that go links static binaries instead of
# dynamically linking against glibc.
# This is useful, when built java-buildpack-memory-calculator is run in
# distributions with older version of GLIBC (e.g. a binary built with golang:1.22.3 image does not run on ubuntu 20.04,
# which seems to be used in our helm smoke tests).
RUN CGO_ENABLED=0 go install github.com/cloudfoundry/java-buildpack-memory-calculator/v4@v4.2.0
RUN ls -la /go/bin/java-buildpack-memory-calculator &&  \
    /go/bin/java-buildpack-memory-calculator  --head-room 25 \
                                              --thread-count 1000 \
                                              --loaded-class-count 10000 \
                                              --total-memory 512G

RUN shasum -a 512 -b /go/bin/java-buildpack-memory-calculator

## TODO: validate shasum of a package (mind AARCH and AMD64)
## TODO: include this package into licenses
RUN curl https://raw.githubusercontent.com/cloudfoundry/java-buildpack-memory-calculator/main/NOTICE \
     > /go/bin/java-buildpack-memory-calculator.NOTICE && \
    cat /go/bin/java-buildpack-memory-calculator.NOTICE

FROM amazonlinux:2

RUN yum -y update && \
    yum -y install shadow-utils java-17-amazon-corretto-devel procps util-linux which gzip tar curl net-tools openssl && \
    groupadd -g 990 app && \
    useradd -r -u 990 -g app app -m

COPY --from=MEMORY_CALCULATOR /go/bin/java-buildpack-memory-calculator* /opt/
COPY entrypoint.sh /app/

ARG YK_ENABLED
RUN if [[ -n "$YK_ENABLED" ]]; then \
      echo "libyjpagent64.so included"; \
      curl -fSsL "https://packages.jetbrains.team/files/p/ij/intellij-dependencies/org/jetbrains/intellij/deps/yourkit/yjpagent/2022.9.162/libyjpagent64.so" \
        -o /home/app/libyjpagent64.so; \
    else \
      echo "libyjpagent64.so excluded"; \
    fi

ADD tbe-*.tar /app/

ARG JQ_ENABLED
RUN if [[ -n "$JQ_ENABLED" ]]; then \
      echo "jq-linux64 included"; \
      curl -LO https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux64 && chmod +x jq-linux64 && cp jq-linux64 /usr/bin/jq; \
    else \
      echo "jq-linux64 excluded"; \
    fi

USER 990
WORKDIR /home/app
CMD /app/entrypoint.sh
