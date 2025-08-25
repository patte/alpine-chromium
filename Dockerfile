FROM alpine:3.22

RUN apk upgrade --no-cache --available \
  && apk add --no-cache \
  chromium \
  ttf-freefont \
  font-noto \
  font-noto-emoji \
  font-wqy-zenhei \
  socat \
  s6-overlay

COPY fonts.conf /etc/fonts/local.conf
RUN fc-cache -f -v

# add user chrome
RUN mkdir -p /usr/src/app \
  && adduser -D chrome \
  && chown -R chrome:chrome /usr/src/app

WORKDIR /usr/src/app

ENV CHROME_BIN=/usr/bin/chromium-browser \
  CHROME_PATH=/usr/lib/chromium/

# fix chrome_crashpad_handler: --database is required
RUN mkdir -p /tmp/.chromium \
  && chown -R chrome:chrome /tmp/.chromium
ENV XDG_CONFIG_HOME=/tmp/.chromium
ENV XDG_CACHE_HOME=/tmp/.chromium

# add s6-overlay services
COPY --chown=chrome:chrome services /etc/services.d/

ENV CHROMIUM_ARGS="--headless --remote-debugging-port=9223 --disable-crash-reporter --no-crashpad --disable-extensions --hide-scrollbars"

EXPOSE 9222

ENTRYPOINT ["/init"]
CMD []
