import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
    // 에이전트 임시 폴더(gitignore 됨) — 번들 산출물·검증 스크립트가 lint 를 빨갛게 만들지 않게
    ".scratch/**",
  ]),
]);

export default eslintConfig;
