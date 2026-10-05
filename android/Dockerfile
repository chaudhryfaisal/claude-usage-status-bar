# Reproducible Android build environment: JDK 17 + Gradle 8.7 + Android SDK 34
FROM eclipse-temurin:17-jdk-jammy

ARG GRADLE_VERSION=8.7
ARG CMDLINE_TOOLS=11076708
ARG PLATFORM=android-34
ARG BUILD_TOOLS=34.0.0

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    GRADLE_USER_HOME=/gradle-cache \
    HOME=/tmp
ENV PATH=${PATH}:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/build-tools/${BUILD_TOOLS}

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl unzip ca-certificates git openssl \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -o /tmp/gradle.zip \
 && unzip -q /tmp/gradle.zip -d /opt \
 && ln -s /opt/gradle-${GRADLE_VERSION}/bin/gradle /usr/local/bin/gradle \
 && rm /tmp/gradle.zip

RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
 && curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip" -o /tmp/cmdline.zip \
 && unzip -q /tmp/cmdline.zip -d ${ANDROID_HOME}/cmdline-tools \
 && mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
 && rm /tmp/cmdline.zip \
 && yes | sdkmanager --licenses > /dev/null \
 && sdkmanager "platform-tools" "platforms;${PLATFORM}" "build-tools;${BUILD_TOOLS}"

# Builds run as the host user (--user), so caches and SDK must be writable by anyone.
RUN mkdir -p /gradle-cache /project && chmod -R 777 /gradle-cache ${ANDROID_HOME} /project

WORKDIR /project
