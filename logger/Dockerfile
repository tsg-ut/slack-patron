FROM ruby:3.4.4-alpine
LABEL maintainer="TSG <info@tsg.ne.jp>"

ARG SRCDIR="/usr/local/slack-patron"

RUN set -x && \
	apk upgrade --update && \
	apk add --update \
	build-base \
	openssl \
	openssl-dev \
	bash && \
	echo 'gem: --no-document' >> /etc/gemrc && \
	wget https://github.com/vishnubob/wait-for-it/raw/master/wait-for-it.sh -O /wait-for-it.sh && \
	chmod +x /wait-for-it.sh

COPY Gemfile ${SRCDIR}/
COPY Gemfile.lock ${SRCDIR}/

WORKDIR ${SRCDIR}

RUN bundle config build.nio4r --with-cflags="-Wno-incompatible-pointer-types" && \
    bundle install

CMD /wait-for-it.sh -t 0 mongo:27017 -- /wait-for-it.sh -t 0 elasticsearch:9200 -- bundle exec ruby logger/logger.rb
