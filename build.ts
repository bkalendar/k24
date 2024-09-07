import { build } from "npm:esbuild";
import {
  denoLoaderPlugin,
  denoResolverPlugin,
} from "jsr:@luca/esbuild-deno-loader";
import { solidPlugin } from "npm:esbuild-plugin-solid";

const result = await build({
  entryPoints: ["index.tsx"],
  outdir: "www/js",
  bundle: true,
  format: "esm",
  treeShaking: true,
  minify: true,
  sourcemap: "linked",
  plugins: [
    denoResolverPlugin(),
    // Solid handles the JSX, so it needs to be sandwiched between the deno plugins
    solidPlugin({
      solid: {
        moduleName: "npm:solid-js/web",
      },
    }),
    denoLoaderPlugin(),
  ],
});

console.log(result);
