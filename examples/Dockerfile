# Multi-stage Dockerfile with BuildKit optimizations
# Supports multi-platform builds (linux/amd64, linux/arm64)

# syntax=docker/dockerfile:1.6
FROM --platform=$BUILDPLATFORM node:20-alpine AS builder

WORKDIR /app

# Copy dependency files first for better layer caching
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY . .

# Build application (if needed)
RUN npm run build 2>/dev/null || echo "No build script found"

# Production stage
FROM node:20-alpine AS production

# Security: Run as non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001

WORKDIR /app

# Copy built application from builder stage
COPY --from=builder --chown=nextjs:nodejs /app/dist ./dist
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/package*.json ./

# Switch to non-root user
USER nextjs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node healthcheck.js || exit 1

# Set environment variables from build args
ARG VERSION
ARG BUILD_DATE
ARG VCS_REF

ENV VERSION=${VERSION:-unknown}
ENV BUILD_DATE=${BUILD_DATE:-unknown}
ENV VCS_REF=${VCS_REF:-unknown}
ENV NODE_ENV=production
ENV PORT=3000

# Metadata labels
LABEL org.opencontainers.image.title="My Service" \
      org.opencontainers.image.description="Production service container" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.vendor="Your Organization" \
      org.opencontainers.image.licenses="MIT"

# Start the application
CMD ["node", "dist/index.js"]

# Alternative: Python/Django example
# =================================
# FROM python:3.11-slim AS builder
# WORKDIR /app
# COPY requirements.txt .
# RUN pip install --user --no-cache-dir -r requirements.txt
# COPY . .
# FROM python:3.11-slim AS production
# WORKDIR /app
# COPY --from=builder /root/.local /root/.local
# COPY --from=builder /app .
# ENV PATH=/root/.local/bin:$PATH
# EXPOSE 8000
# CMD ["gunicorn", "--bind", "0.0.0.0:8000", "myapp.wsgi"]
