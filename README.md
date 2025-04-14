# alpine-chromium

Run headless chromium in a minimal alpine container.
This is a fork of [jlandure/alpine-chrome](https://github.com/jlandure/alpine-chrome) adapted to new alpine and chrome versions plus some fonts.

Features:
- [x] alpine 3.21, chromium 135+
- [x] Small image size: ~310MB 
- [x] Fonts: `font-noto`, `font-noto-emoji`, `font-wqy-zenhei`, `ttf-freefont`
- [x] Works with or without `--no-sandbox` thanks to a seccomp profile 
- [x] socat to access debug port (because chromium removed `remote-debugging-address=0.0.0.0`)
- [x] s6-overlay to manage chromium and socat processes
- [x] GitHub action to build (weekly) and push the image to ghcr.io
- [x] Images for `linux/amd64` and `linux/arm64`

Image:
```
ghcr.io/patte/alpine-chromium
```

## Usage

### docker run
```bash
docker run --rm \
  --security-opt seccomp=./chrome.json \
  -p 9222:9222 \
  ghcr.io/patte/alpine-chromium
```

### docker-compose
```yaml
services:
  chrome:
    image: ghcr.io/patte/alpine-chromium
    security_opt:
      - seccomp=./chrome.json
    ports:
      - '9222:9222'
```

### Overwriting default chrome args
The `Dockerfile` sets default args for chromium in [`CHROMIUM_ARGS`](./Dockerfile#L35). You can overwrite them by setting the `CHROMIUM_ARGS` environment variable in your `docker-compose.yml` file. Make sure to keep at least: `--headless --remote-debugging-port=9223 --disable-crash-reporter --no-crashpad`.

Eg. without `security_opt` but `--no-sandbox`:
```yaml
services:
  chrome:
    image: ghcr.io/patte/alpine-chromium
    ports:
      - '9222:9222'
    environment:
      CHROMIUM_ARGS: '--headless --no-sandbox --no-zygote --remote-debugging-port=9223 --disable-crash-reporter --no-crashpad'
```

### Puppeteer
Connect puppeteer to the running container:
```ts
const browser = await puppeteer.connect({
  browserURL: 'http://localhost:9222',
});
```

Or if you want to use websockets, get `webSocketDebuggerUrl` from `localhost:9222/json/version`:
```ts
const chromeVersion = await fetch('http://localhost:9222/json/version').then((res) => {
  if (!res.ok) {
    throw new Error(`Can't connect to Chrome: ${res.statusText}`);
  }
  return res.json();
});

const browser = await puppeteer.connect({
  browserWSEndpoint: chromeVersion.webSocketDebuggerUrl,
});
```

## Build
To manually build the image, run the following command:
```bash
docker build -t localhost/alpine-chromium .
```

## Credits
Inspired by:
- [jlandure/alpine-chrome](https://github.com/jlandure/alpine-chrome)
- [browserless/browserless](https://github.com/browserless/browserless)
