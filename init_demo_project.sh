#!/bin/bash

# 项目根目录
PROJECT_ROOT="nextjs_esm_npm_demo"
mkdir -p "$PROJECT_ROOT"

# 创建目录结构
mkdir -p "$PROJECT_ROOT/esm-server/storage"
mkdir -p "$PROJECT_ROOT/verdaccio/storage"
mkdir -p "$PROJECT_ROOT/nextjs-app/pages" "$PROJECT_ROOT/nextjs-app/lib"

# 1. docker-compose.yml
cat << 'EOF' > "$PROJECT_ROOT/docker-compose.yml"
services:
  verdaccio:
    image: verdaccio/verdaccio:latest
    container_name: verdaccio
    ports:
      - "4873:4873"
    volumes:
      - ./verdaccio/storage:/verdaccio/storage
      - ./verdaccio/config.yaml:/verdaccio/conf/config.yaml
      - ./verdaccio/htpasswd:/verdaccio/conf/htpasswd
    networks:
      - app-network
  esm-server:
    build:
      context: ./esm-server
      dockerfile: Dockerfile
    container_name: esm_server
    ports:
      - "8080:8080"
    volumes:
      - ./esm-server/storage:/app/storage
      - ./esm-server/config.json:/app/config.json
    command: ./esmd --config=/app/config.json
    depends_on:
      - verdaccio
    networks:
      - app-network
  local-modules:
    build:
      context: ./local-modules
      dockerfile: Dockerfile
    container_name: local_modules
    volumes:
      - ./local-modules:/app
    environment:
      - NODE_ENV=development
    depends_on:
      - verdaccio
      - esm-server
    networks:
      - app-network
  nextjs-app:
    build:
      context: ./nextjs-app
      dockerfile: Dockerfile
    container_name: nextjs_app
    ports:
      - "3000:3000"
    volumes:
      - ./nextjs-app:/app
      - /app/node_modules
    environment:
      - NODE_ENV=development
      - ESM_SERVER_URL=http://esm-server:8080
    depends_on:
      - verdaccio
      - esm-server
      - local-modules
    command: npm run dev
    networks:
      - app-network
networks:
  app-network:
    driver: bridge
EOF

# 2. esm-server/Dockerfile
cat << 'EOF' > "$PROJECT_ROOT/esm-server/Dockerfile"
FROM golang:1.23 AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y git

RUN git clone https://github.com/esm-dev/esm.sh.git .

RUN go mod download

RUN CGO_ENABLED=0 GOOS=linux go build -o esmd server/cmd/main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/esmd .
COPY config.json /app/config.json

# Install required packages automatically
RUN apk add --no-cache libgcc libstdc++ gcompat

CMD ["./esmd"]
EOF

# 3. esm-server/config.json
cat << 'EOF' > "$PROJECT_ROOT/esm-server/config.json"
{
  "port": 8080,
  "storageDir": "/app/storage",
  "npmRegistry": "http://verdaccio:4873",
  "credentials": {
    "username": "test",
    "password": "test"
  },
  "proxy": {
    "http://verdaccio:4873/": {
      "target": "https://registry.npmjs.org/",
      "changeOrigin": true
    }
  }
}
EOF

# 4. verdaccio/config.yaml
cat << 'EOF' > "$PROJECT_ROOT/verdaccio/config.yaml"
storage: /verdaccio/storage
auth:
  htpasswd:
    file: /verdaccio/conf/htpasswd
    max_users: 100
uplinks:
  npmjs:
    url: https://registry.npmjs.org/
packages:
  '@*/*':
    access: $all
    publish: $authenticated
    proxy: npmjs
  '**':
    access: $all
    publish: $authenticated
    proxy: npmjs
logs:
  - { type: stdout, format: pretty, level: info }
EOF

# 5. verdaccio/htpasswd
cat << 'EOF' > "$PROJECT_ROOT/verdaccio/htpasswd"
test:$2a$10$EcIlyfhipDupQFwI7rFZSOGjsVqPgeexRHk9JV5UGR8lWS7TO92JK:autocreated 2025-03-26T12:22:43.545Z
EOF

# 6. nextjs-app/Dockerfile
cat << 'EOF' > "$PROJECT_ROOT/nextjs-app/Dockerfile"
FROM node:18
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
CMD ["npm", "run", "dev"]
EOF

# 7. nextjs-app/package.json
cat << 'EOF' > "$PROJECT_ROOT/nextjs-app/package.json"
{
  "name": "nextjs-app",
  "version": "1.0.0",
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start"
  },
  "dependencies": {
    "next": "^14.0.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  }
}
EOF

# 8. nextjs-app/lib/bannerLoader.js
cat << 'EOF' > "$PROJECT_ROOT/nextjs-app/lib/bannerLoader.js"
export async function loadBannerComponent(uid) {
  const esmServerUrl = process.env.ESM_SERVER_URL || 'http://localhost:8080';
  const bannerMap = {
    'user1': `${esmServerUrl}/@my-org/banner-v1`,
    'user2': `${esmServerUrl}/@my-org/banner-v2`,
    'default': `${esmServerUrl}/@my-org/banner`
  };

  const url = bannerMap[uid] || bannerMap['default'];
  const { default: BannerComponent } = await import(/* webpackIgnore: true */ url);
  return BannerComponent;
}
EOF

# 9. nextjs-app/pages/index.js
cat << 'EOF' > "$PROJECT_ROOT/nextjs-app/pages/index.js"
import { useEffect, useState } from 'react';
import { loadBannerComponent } from '../lib/bannerLoader';

export default function Home() {
  const [Banner, setBanner] = useState(null);
  const [uid, setUid] = useState('anonymous');

  useEffect(() => {
    let idx = 0;
    setInterval(() => {
      setUid(`user${++idx % 3}`);
    }, 3000);
  }, []);

  useEffect(() => {
    async function fetchBanner() {
      try {
        const BannerComponent = await loadBannerComponent(uid);
        setBanner(() => BannerComponent);
      } catch (error) {
        console.error('Failed to load banner:', error);
      }
    }
    fetchBanner();
  }, [uid]);

  return (
    <div>
      <p>{ uid }</p>
      {Banner ? <Banner /> : <div>Loading Banner...</div>}
    </div>
  );
}
EOF

# strat create local npm modules demo comps
cd "$PROJECT_ROOT"
mkdir -p local-modules/my-react-comp/src

# Create Dockerfile
cat > local-modules/Dockerfile << 'EOL'
FROM node:18
WORKDIR /app
COPY ./* .
CMD ["bash", "build.sh"]
EOL

# Create build.sh
cat > local-modules/build.sh << 'EOL'
#!/bin/bash

# 登陆 npm
node login.js

# 进入项目目录
cd my-react-comp || { echo "目录 my-react-comp 不存在，请先运行 init.sh"; exit 1; }

# 构建项目
echo "开始构建..."
npm install || { echo "安装依赖失败，请检查错误"; exit 1; }
npm run build || { echo "构建失败，请检查错误"; exit 1; }

# 配置 Verdaccio 的 npm 源
npm set registry http://verdaccio:4873/

# echo "登录到 Verdaccio..."
# npm login --registry http://verdaccio:4873

# 检查登录状态
npm whoami --registry http://verdaccio:4873/ || {
    echo "登录失败，请检查 Verdaccio 是否运行在 http://verdaccio:4873/";
    exit 1;
}

# 发布到 Verdaccio
echo "发布到 Verdaccio..."
npm publish || { echo "发布失败，请检查错误"; exit 1; }

# 更新模块为 v1
sed -i 's/"@my-org\/banner"/"@my-org\/banner-v1"/g' ./package.json
sed -i 's/This is default banner/This is the banner v1/g' ./src/index.tsx
sed -i 's/color: var(--color, red);/color: var(--color, blue);/g' ./src/index.module.less

npm run build && npm publish || { echo "发布 v1 版本失败"; exit 1; }

# 更新模块为 v2
sed -i 's/"@my-org\/banner-v1"/"@my-org\/banner-v2"/g' ./package.json
sed -i 's/This is the banner v1/This is the banner v2/g' ./src/index.tsx
sed -i 's/color: var(--color, blue);/color: var(--color, goldenrod);/g' ./src/index.module.less

npm run build && npm publish || { echo "发布 v2 版本失败"; exit 1; }

# 恢复默认 npm 源
npm set registry https://registry.npmjs.org/

echo "组件已成功发布到本地 Verdaccio 服务: http://verdaccio:4873/"
EOL

chmod +x local-modules/build.sh

# Create my-react-comp/README.md
cat > local-modules/my-react-comp/README.md << 'EOL'
# my-react-comp

A simple React component with LESS styling and TypeScript support.

## Installation

```bash
npm install my-react-comp
```

## Usage

```javascript
import Comp from 'my-react-comp';

function App() {
  return <Comp text="Hello World" color="blue" />;
}
```

## Props

- `text` (string, optional): The text to display. Defaults to "This is Comp".
- `color` (string, optional): The text color. Defaults to "red".

## License

MIT
EOL

# Create my-react-comp/package.json
cat > local-modules/my-react-comp/package.json << 'EOL'
{
  "name": "@my-org/banner",
  "version": "1.0.0",
  "description": "A simple React component with LESS styling",
  "main": "dist/index.js",
  "module": "dist/index.js",
  "types": "dist/index.d.ts",
  "type": "module",
  "files": [
    "dist",
    "src"
  ],
  "scripts": {
    "build": "rollup -c",
    "prepublishOnly": "npm run build",
    "type-check": "tsc --noEmit"
  },
  "keywords": [
    "react",
    "component",
    "less",
    "esm"
  ],
  "author": "Your Name",
  "license": "MIT",
  "peerDependencies": {
    "react": "^17.0.0 || ^18.0.0"
  },
  "devDependencies": {
    "@babel/core": "7.26.10",
    "@babel/preset-env": "7.26.8",
    "@babel/preset-react": "7.25.9",
    "@babel/preset-typescript": "7.27.0",
    "@rollup/plugin-babel": "6.0.4",
    "@rollup/plugin-commonjs": "26.0.2",
    "@rollup/plugin-node-resolve": "15.3.0",
    "@rollup/plugin-terser": "0.4.4",
    "@rollup/plugin-typescript": "11.1.6",
    "@types/react": "18.3.12",
    "less": "4.2.0",
    "rollup": "4.37.0",
    "rollup-plugin-dts": "6.2.1",
    "rollup-plugin-postcss": "4.0.2",
    "typescript": "5.8.2"
  }
}
EOL

# Create my-react-comp/rollup.config.js
cat > local-modules/my-react-comp/rollup.config.js << 'EOL'
import resolve from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import postcss from 'rollup-plugin-postcss';
import terser from '@rollup/plugin-terser';
import babel from '@rollup/plugin-babel';
import typescript from '@rollup/plugin-typescript';
import path from 'path';
import crypto from 'crypto';
import { createFilter } from '@rollup/pluginutils';

export default {
  input: 'src/index.tsx',
  output: {
    file: 'dist/index.js',
    format: 'esm',
    sourcemap: true
  },
  plugins: [
    resolve({
      extensions: ['.js', '.jsx', '.ts', '.tsx']
    }),
    commonjs({
      include: 'node_modules/**',
      transformMixedEsModules: true
    }),
    babel({
      exclude: 'node_modules/**',
      babelHelpers: 'bundled',
      extensions: ['.js', '.jsx', '.ts', '.tsx'],
      presets: [
        '@babel/preset-env',
        ['@babel/preset-react', { runtime: 'automatic' }],
        '@babel/preset-typescript'
      ]
    }),
    // 自定义插件强制清除缓存文件
    {
      name: 'force-clean-cache',
      buildStart() {
        // 强制重新计算哈希值
        this.cache.set('css-hash-seed', Date.now().toString());
      }
    },
    postcss({
      modules: {
        getJSON(id, exportTokens, options) {
          // 处理默认的JSON输出，确保每次构建都写入新的映射
          if (options && options.writeJSON) {
            options.writeJSON(id, exportTokens);
          }
        },
        generateScopedName: (name, filename, css) => {
          // 获取完整文件路径，确保唯一性
          const relativePath = path.relative(process.cwd(), filename);
          // 将文件路径和内容结合以生成哈希
          const hashInput = css + relativePath + Date.now();
          const hash = crypto
            .createHash('md5')
            .update(hashInput)
            .digest('hex')
            .substring(0, 8);

          // 处理文件名 - 移除 .module 部分
          let baseName = path.basename(filename);
          if (baseName.includes('.module.')) {
            baseName = baseName.replace('.module', '');
          }
          baseName = path.basename(baseName, path.extname(baseName));

          return `${baseName}_${name}_${hash}`;
        }
      },
      // 强制禁用缓存
      extract: false,
      autoModules: false,
      minimize: true,
      use: ['less'],
      // 添加这个选项来确保插件能识别所有的样式文件
      include: '**/*.less'
    }),
    typescript({
      declaration: true,
      declarationDir: 'dist',
      rootDir: 'src'
    }),
    terser()
  ],
  external: ['react', 'prop-types', 'react/jsx-runtime'],
  // 禁用构建缓存
  cache: false,
  // 增加监视选项以确保文件变更被正确探测
  watch: {
    clearScreen: false,
    include: 'src/**'
  }
};
EOL

# Create my-react-comp/tsconfig.json
cat > local-modules/my-react-comp/tsconfig.json << 'EOL'
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "jsx": "react-jsx",
    "declaration": true,
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "moduleResolution": "node",
    "allowSyntheticDefaultImports": true
  },
  "include": ["src/**/*", "src/global.d.ts"],
  "exclude": ["node_modules", "dist"]
}
EOL

# Create my-react-comp/src/global.d.ts
cat > local-modules/my-react-comp/src/global.d.ts << 'EOL'
declare module '*.module.less' {
  const classes: { [key: string]: string };
  export default classes;
}
EOL

# Create my-react-comp/src/index.d.ts
cat > local-modules/my-react-comp/src/index.d.ts << 'EOL'
import { FC } from 'react';

export interface CompProps {
  text?: string;
  color?: string;
}

declare const Comp: FC<CompProps>;
export default Comp;
EOL

# Create my-react-comp/src/index.module.less
cat > local-modules/my-react-comp/src/index.module.less << 'EOL'
.container {
  color: var(--color, red);
  font-size: 16px;
  padding: 10px;
  border: 1px solid #ccc;
}
EOL

# Create my-react-comp/src/index.tsx
cat > local-modules/my-react-comp/src/index.tsx << 'EOL'
import React from 'react';
import PropTypes from 'prop-types';
import styles from './index.module.less';

interface CompProps {
  text?: string;
  color?: string;
}

const Comp: React.FC<CompProps> = ({
  text = 'This is default banner'
}) => {
  return (
    <div className={styles.container}>
      <p>{text}</p>
    </div>
  );
};

Comp.propTypes = {
  text: PropTypes.string,
  color: PropTypes.string
};

export default Comp;
EOL

# Create login.js
cat > local-modules/login.js << 'EOL'
const { spawn } = require('child_process');

const username = 'test';
const password = 'test';
const email = 'test@test.com';
const registry = 'http://verdaccio:4873/';

const npmLoginuser = spawn('npm', ['login', '--registry', registry]);

npmLoginuser.stdout.on('data', (data) => {
  const output = data.toString();
  if (output.includes('Username:')) {
    npmLoginuser.stdin.write(username + '\n');
  } else if (output.includes('Password:')) {
    npmLoginuser.stdin.write(password + '\n');
  } else if (output.includes('Email:')) {
    npmLoginuser.stdin.write(email + '\n');
  }
});

npmLoginuser.on('close', (code) => code === 0 ? console.log('✅ npm login successful!') : console.error(`❌ npmLoginuser close ${code}`));
EOL

cd ..
# end create local npm modules demo comps

echo "目录结构和文件已生成！"
echo "请进入 $PROJECT_ROOT 目录并运行 'docker-compose up --build' 来启动服务。"
