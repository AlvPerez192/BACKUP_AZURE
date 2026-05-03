# =============================================================================
# Dockerfile multi-stage para la app web del TFG
# =============================================================================
# - Stage 1 (deps): instala dependencias en una imagen completa
# - Stage 2 (runtime): copia solo lo necesario a una imagen alpine minima
# Resultado: imagen final ~150 MB en lugar de ~1 GB
# =============================================================================

# ----- Stage 1: instalar dependencias -----
FROM node:20-alpine AS deps

WORKDIR /app

COPY package.json ./
# Sin package-lock.json a proposito (no lo commiteo en este TFG simplificado).
# En produccion deberia haber lock + npm ci en lugar de npm install.
RUN npm install --omit=dev --no-audit --no-fund

# ----- Stage 2: imagen final -----
FROM node:20-alpine AS runtime

# Usuario no-root (buena practica)
RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

# Copiar deps desde stage anterior
COPY --from=deps --chown=app:app /app/node_modules ./node_modules

# Copiar codigo fuente
COPY --chown=app:app server.js ./
COPY --chown=app:app views ./views
COPY --chown=app:app public ./public

USER app

EXPOSE 3000

# Healthcheck a nivel Docker (independiente del de K8s)
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

ENV NODE_ENV=production
ENV APP_PORT=3000

CMD ["node", "server.js"]
