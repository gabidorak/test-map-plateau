# syntax=docker/dockerfile:1
# PTA Online accounts service (plateau_accounts/app.py). Built for the host's architecture, or cross-built:
#   docker buildx build --platform linux/arm64 server/accounts
# Nothing runs inside the target image while building (no emulation needed for arm64): the dependencies' wheels for
# the target (manylinux: glibc up to python:3.12-slim's 2.36) are fetched by the build machine's own Python.
FROM --platform=$BUILDPLATFORM python:3.12-slim AS deps
ARG TARGETARCH
COPY requirements.txt /
RUN case "$TARGETARCH" in arm64) arch=aarch64 ;; amd64) arch=x86_64 ;; *) echo "unsupported $TARGETARCH"; exit 1 ;; esac \
    && pip install --no-cache-dir --target /deps --only-binary=:all: --implementation cp --python-version 3.12 \
       $(for v in 2014 _2_17 _2_24 _2_26 _2_28 _2_34 _2_36; do echo "--platform manylinux${v}_$arch"; done) \
       -r /requirements.txt

FROM python:3.12-slim
COPY --from=deps /deps /opt/deps
COPY plateau_accounts /app/plateau_accounts
COPY banned_words.txt common_passwords.txt /app/
COPY --chmod=755 plateau-admin /usr/local/bin/plateau-admin
ENV PYTHONPATH=/opt/deps:/app PYTHONUNBUFFERED=1 PLATEAU_ACCOUNTS_DB=/data/accounts.db PLATEAU_BACKUP_DIR=/backups
WORKDIR /app
VOLUME /data
EXPOSE 8000
CMD ["python", "-m", "plateau_accounts.serve"]
