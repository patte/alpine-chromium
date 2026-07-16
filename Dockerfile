FROM alpine:3.24

# chromium-swiftshader provides the vk_swiftshader Vulkan ICD: since
# Chromium 150, ANGLE's SwiftShader backend initializes via Vulkan and the
# GPU process crash-loops without it (issue #21).
RUN apk upgrade --no-cache --available \
  && apk add --no-cache \
  chromium \
  chromium-swiftshader \
  ttf-freefont \
  font-noto \
  font-noto-emoji \
  font-wqy-zenhei \
  socat \
  s6-overlay

# font-wqy-zenhei's 44-wqy-zenhei.conf aliases the generic families to
# WenQuanYi ahead of local.conf, so latin text would render with WenQuanYi
# glyphs instead of the Noto fonts preferred below. Dropping it leaves CJK
# fallback intact (coverage-based); 91-wqy-zenhei.conf (render settings)
# stays.
RUN rm /etc/fonts/conf.d/44-wqy-zenhei.conf
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
