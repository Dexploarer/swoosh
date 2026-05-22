;; Hello Wasm — reference WebAssembly plugin shipped with Swoosh.
;;
;; The module exports one function (`add`) that the host's
;; WasmPluginExecutor invokes when the agent calls the `wasm.add` tool.
;; The plugin imports nothing — no WASI, no host bindings — and so runs
;; in the strongest sandbox WasmKit can give us: it can read/write only
;; its own linear memory and has no side effects.
;;
;; Source format is `.wat` (WebAssembly text); the host compiles it to a
;; binary `.wasm` at load time via WAT's `wat2wasm`. Authors who prefer to
;; ship a precompiled `.wasm` can do that and point the manifest at it
;; directly — the executor handles both extensions.

(module
  (func $add (export "add") (param $a i32) (param $b i32) (result i32)
    local.get $a
    local.get $b
    i32.add)
)
