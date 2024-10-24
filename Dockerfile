FROM golang:1.22.7 as MEMORY_CALCULATOR
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

FROM alpine:3.15.11

#java coretto 17 | bash is required by entrypoint script | openssl coreutils jq curl are required by tests
RUN wget -O /etc/apk/keys/amazoncorretto.rsa.pub  https://apk.corretto.aws/amazoncorretto.rsa.pub && \
    echo "https://apk.corretto.aws/" >> /etc/apk/repositories && \
    apk add --update --no-cache amazon-corretto-17 bash openssl coreutils jq curl && \
    addgroup -g 990 app && \
    adduser --system -u 990 -g app app
ENV JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto

# dev tools
ARG YK_ENABLED
RUN if [[ -n "$YK_ENABLED" ]]; then \
      arch=$(arch); \
      if [[ "$arch" == aarch* || "$arch" == arm* ]]; then architecture="a"; else architecture=""; fi && \
      wget "https://packages.jetbrains.team/files/p/ij/intellij-dependencies/org/jetbrains/intellij/deps/yourkit/yjpagent/2022.9.162/libyjpagent64${architecture}.so" -O /home/app/libyjpagent64.so; \
    fi

ARG ADDITIONAL_SPRING_PROFILES=none
ENV ADD_SPRING_PROFILES=$ADDITIONAL_SPRING_PROFILES

COPY --from=MEMORY_CALCULATOR /go/bin/java-buildpack-memory-calculator* /opt/

USER 990
WORKDIR /home/app
CMD /app/entrypoint.sh

COPY entrypoint.sh /app/
ADD tbe-*.tar /app/
