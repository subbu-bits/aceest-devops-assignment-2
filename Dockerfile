FROM python:3.12-slim

# Version baked into the image. Empty = use the VERSION file.
# (scripts/release_all_versions.sh passes --build-arg APP_VERSION=1.0 etc.)
ARG APP_VERSION=""

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    ACEEST_DB=/app/data/aceest_fitness.db \
    APP_VERSION=${APP_VERSION}

LABEL org.opencontainers.image.title="ACEest Fitness & Gym" \
      org.opencontainers.image.source="https://github.com/subbu-bits/aceest-devops-assignment-2"

WORKDIR /app

RUN useradd --create-home --uid 1000 appuser \
    && mkdir -p /app/data \
    && chown -R appuser:appuser /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=appuser:appuser . .

USER appuser
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# --access-logfile - prints every request to the pod log
# (used to prove the shadow deployment receives mirrored traffic).
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:app"]
