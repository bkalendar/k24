import { DAY, WEEK } from "jsr:@std/datetime";

const module = await WebAssembly.compile(
  Deno.readFileSync("zig-out/bin/mybk_app.wasm"),
);
const instance = await WebAssembly.instantiate(module, {
  host: {
    beginCalendar() {},
    endCalendar() {},
    doSemester(year: number, semester: number) {
      console.log(year, semester);
    },
    log(ptr: number, size: number) {
      const arr = new Uint8Array(instance.exports.memory.buffer, ptr, size);
      console.log(new TextDecoder().decode(arr));
    },
    getUTC(year: number, week: number, weekday: number) {
      let d = +Date.UTC(year, 0, 4);
      // offset new year into index 0 week
      d += (week - 1) * WEEK;
      // offset weekday
      d -= (new Date(d).getUTCDay() + 6) % 7 * DAY;
      d += (weekday - 2) * DAY;
      return d / 1000;
    },
    // deno-lint-ignore no-explicit-any
  } as any,
});

const s =
  "20241	GK5924	Quản lý dự án	3	3	1	3	13 - 16	18:00 - 20:29	B4-501	BK-LTK	37|38|39|40|--|42|43|44|45|46|47|";

const ptr = instance.exports.alloc(s.length);
const arr = new Uint8Array(instance.exports.memory.buffer, ptr, s.length);

new TextEncoder().encodeInto(s, arr);

instance.exports.parse(ptr, s.length);
