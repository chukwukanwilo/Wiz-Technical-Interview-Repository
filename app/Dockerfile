# simple Node app
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY src ./src
COPY wizexercise.txt /app/wizexercise.txt
ENV PORT=3000
CMD ["node", "src/server.js"]
