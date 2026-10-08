FROM node:24-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY producteur.mjs ./
# Dossier des listes d'événements attendus, partagé avec le tableau de bord en local.
RUN mkdir /lots && chown node:node /lots
USER node
ENTRYPOINT ["node", "producteur.mjs"]
