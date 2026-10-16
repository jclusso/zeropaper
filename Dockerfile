# syntax=docker/dockerfile:1
# check=error=true

# Production image. Use with docker compose (see docker-compose.yml) or build by hand:
#   docker build -t zeropaper .

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.7
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Runtime packages: poppler and qpdf for PDF work, Tesseract for local OCR,
# ghostscript for ocrmypdf, libvips for thumbnails.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 libvips postgresql-client python3 python3-venv \
      poppler-utils qpdf ghostscript tesseract-ocr tesseract-ocr-eng tesseract-ocr-osd && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# ocrmypdf from PyPI rather than Debian: version 17 rasterizes pages with
# pdfium, while Debian's 16.x relies on its Ghostscript, which fails on some
# scans that carry an old OCR layer ("Ghostscript rasterizing failed").
ARG OCRMYPDF_VERSION=17.13.0
RUN python3 -m venv /opt/ocrmypdf && \
    /opt/ocrmypdf/bin/pip install --no-cache-dir "ocrmypdf==${OCRMYPDF_VERSION}" pypdfium2 && \
    ln -s /opt/ocrmypdf/bin/ocrmypdf /usr/local/bin/ocrmypdf

# Production environment, jemalloc for lower memory use, and jobs inside Puma
# so one container runs the whole app.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    SOLID_QUEUE_IN_PUMA="true" \
    HTTP_PORT="3000" \
    TARGET_PORT="3001" \
    PORT="3001" \
    INGEST_DIR="/rails/storage/ingest" \
    BACKUP_DIR="/rails/storage/backups" \
    MODELS_DIR="/rails/storage/models"

# Throw-away build stage to reduce size of final image
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

# onnxruntime (used by informers for local embeddings) installs as a
# precompiled platform gem for x86_64-linux and aarch64-linux.
# The gems' bootsnap cache is set aside so the final image keeps it in its own
# layer, which only changes with the Gemfile and so is not shipped on every
# deploy. The app's own files are compiled at runtime on first use.
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile && \
    mv tmp/cache/bootsnap /bootsnap

COPY . .

# Precompile assets (including Tailwind) without the real secret.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Final stage for app image
FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /rails/storage/ingest/private /rails/storage/backups /rails/storage/models && \
    chown -R rails:rails /rails

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /bootsnap /rails/tmp/cache/bootsnap
COPY --chown=rails:rails --from=build --exclude=tmp/cache /rails /rails

USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Thruster listens on 3000 and proxies to Puma on 3001.
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:3000/up || exit 1
CMD ["./bin/thrust", "./bin/rails", "server"]
