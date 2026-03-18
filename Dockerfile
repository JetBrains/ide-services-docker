ARG JDK_OR_JRE=jdk
ARG JAVA_VERSION=21
FROM registry.jetbrains.team/p/toolbox-enterprise/public/base-temurin:${JAVA_VERSION}-${JDK_OR_JRE}-alpine-68

ARG YK_ENABLED
ENV YK_ENABLED=${YK_ENABLED}
RUN if [[ -n "$YK_ENABLED" ]]; then \
      arch=$(arch); \
      if [[ "$arch" == aarch* || "$arch" == arm* ]]; then architecture="a"; else architecture=""; fi && \
      wget "https://packages.jetbrains.team/files/p/ij/intellij-dependencies/org/jetbrains/intellij/deps/yourkit/yjpagent/2022.9.162/libyjpagent64${architecture}.so" -O /home/app/libyjpagent64.so; \
    fi


ARG CUSTOM_ACTIVE_PROFILE_GROUP=none
ENV SET_ACTIVE_PROFILE_GROUP=${CUSTOM_ACTIVE_PROFILE_GROUP}

CMD ["/app/entrypoint.sh"]

COPY entrypoint.sh /app/
ADD tbe-*.tar /app/
