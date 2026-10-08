FROM node:24-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY server.mjs sources.mjs gcp.mjs ./
COPY public ./public
# Dossier des listes d'événements attendus, partagé avec le producteur en local.
RUN mkdir /lots && chown node:node /lots
USER node
ENV PORT=8080
EXPOSE 8080
HEALTHCHECK --interval=5s --timeout=3s --retries=24 CMD node -e "fetch('http://127.0.0.1:8080/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "server.mjs"]
