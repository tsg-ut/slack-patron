FROM rwynn/monstache-builder-cache-rel6:1.0.7 AS build-app

RUN mkdir /app
WORKDIR /app
RUN git clone --depth 1 --branch v6.7.10 https://github.com/rwynn/monstache.git .
RUN make release
COPY ./text_embedding.go .
RUN go build -buildmode=plugin -o build/plugin.so text_embedding.go


FROM rwynn/monstache-alpine:3.15.0

RUN cd /tmp && \
	wget https://github.com/vishnubob/wait-for-it/raw/master/wait-for-it.sh -O /wait-for-it.sh && \
	chmod +x /wait-for-it.sh

RUN apk add bash
RUN echo 'https://dl-cdn.alpinelinux.org/alpine/v3.6/main' >> /etc/apk/repositories && \
	echo 'https://dl-cdn.alpinelinux.org/alpine/v3.6/community' >> /etc/apk/repositories && \
	apk add mongodb mongodb-tools

COPY run.sh .
COPY monstache.toml .

COPY --from=build-app /app/build/linux-amd64/monstache /bin/monstache
COPY --from=build-app /app/build/plugin.so /bin/plugin.so
ENTRYPOINT /wait-for-it.sh mongo:27017 -t 0 -- /wait-for-it.sh elasticsearch:9200 -t 0 -- bash run.sh
