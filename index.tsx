import { render } from "npm:solid-js/web";
import { createSignal } from "npm:solid-js";

function Bar() {
  const [value, setValue] = createSignal(0);
  setInterval(() => {
    setValue(value() + 1);
  }, 1000);
  return <div>Incremented value {value()}</div>;
}

render(() => <Bar />, document.getElementById("root")!);
