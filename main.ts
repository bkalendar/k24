import { instantiate } from "./zig-out/js/parser.js";
import { DAY, HOUR } from "jsr:@std/datetime";

function dayOfWeek(d: number): number {
  return ((new Date(d).getDay() + 6) % 7) + 2;
}

const { parse } = await instantiate(
  (path) =>
    fetch(
      new URL(`./zig-out/js/${path.slice(0, -5)}.wasm`, import.meta.url),
    ).then(WebAssembly.compileStreaming),
  {
    "bkalendar:k24/console": console,
    "bkalendar:k24/calendar": {},
    epoch: {
      default(year) {
        console.log(year);
        // start with new year
        let d = +Date.UTC(year, 0, 4);
        // offset weekday
        d -= (dayOfWeek(d) - 2) * DAY;
        // timezone
        d -= 7 * HOUR;
        console.log(new Date(d));

        return BigInt(Math.trunc(d / 1000));
      },
    },
  },
);

console.log(
  parse(
    "20232\tMT1005\tGiải tích 2\t4\t4\tL18\t6\t7 - 10\t12:00 - 14:50\tH3-301\tBK-DAn\t02|03|04|05|--|--|08|09|10|--|--|--|--|--|16|17|18|19|20|21|22|23|",
  ),
);
