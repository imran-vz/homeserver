FROM ghcr.io/actions/actions-runner:2.337.0@sha256:e5496277be5d09bc968b3d64911b74e219ac4a3f2edce956a3ecf9271bea1ef4

ARG RUNNER_UID=501
ARG RUNNER_GID=20

USER root

# Match the macOS owner of the bind-mounted runner state directory without
# recursively changing the ownership of the large runner distribution layer.
RUN sed -i "s/^runner:x:1001:1001:/runner:x:${RUNNER_UID}:${RUNNER_GID}:/" /etc/passwd

COPY --chmod=755 entrypoint.sh /usr/local/bin/github-runner-entrypoint

USER runner
ENTRYPOINT ["/usr/local/bin/github-runner-entrypoint"]
